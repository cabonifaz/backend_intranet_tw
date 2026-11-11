using System.Net;
using System.Net.Sockets;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Guardas anti-SSRF para descargar el manual de un suministro (la URL la escribe un usuario de la intranet, así que no es de fiar):
///  - solo https, sin usuario ni contraseña en la URL, en el puerto 443 y con un nombre de servidor que no sea interno (localhost, .local, .internal…);
///  - el nombre se resuelve y TODAS las direcciones deben ser públicas (nada de loopback, redes privadas, link-local —incluida la de metadatos de la nube—,
///    CGNAT, multicast ni reservadas), y la conexión se hace a la dirección ya validada (evita el cambio de DNS entre la validación y la conexión);
///  - las redirecciones se siguen a mano (máx. 3) y cada destino pasa por las mismas guardas.
/// </summary>
public static class GuardaUrlManual
{
    public const int MaxRedirecciones = 3;
    public const int MaxLongitudUrl = 500;

    private static readonly string[] SufijosInternos = [".local", ".localhost", ".internal", ".intranet", ".lan", ".home", ".corp", ".localdomain"];

    /// <summary>true si la dirección es pública (se puede conectar desde el servidor sin llegar a nada interno).</summary>
    public static bool EsIpPublica(IPAddress ip)
    {
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        if (IPAddress.IsLoopback(ip) || ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any) || ip.Equals(IPAddress.Broadcast)) return false;

        if (ip.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = ip.GetAddressBytes();
            return !(b[0] == 0                                          // 0.0.0.0/8
                  || b[0] == 10                                         // 10.0.0.0/8
                  || (b[0] == 100 && b[1] is >= 64 and <= 127)          // 100.64.0.0/10 (CGNAT)
                  || b[0] == 127                                        // 127.0.0.0/8
                  || (b[0] == 169 && b[1] == 254)                       // 169.254.0.0/16 (link-local y metadatos de la nube)
                  || (b[0] == 172 && b[1] is >= 16 and <= 31)           // 172.16.0.0/12
                  || (b[0] == 192 && b[1] == 0 && b[2] is 0 or 2)       // 192.0.0.0/24 y 192.0.2.0/24
                  || (b[0] == 192 && b[1] == 168)                       // 192.168.0.0/16
                  || (b[0] == 198 && b[1] is 18 or 19)                  // 198.18.0.0/15
                  || (b[0] == 198 && b[1] == 51 && b[2] == 100)         // 198.51.100.0/24
                  || (b[0] == 203 && b[1] == 0 && b[2] == 113)          // 203.0.113.0/24
                  || b[0] >= 224);                                      // multicast y reservadas
        }

        if (ip.AddressFamily == AddressFamily.InterNetworkV6)
        {
            if (ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || ip.IsIPv6Multicast || ip.IsIPv6UniqueLocal || ip.IsIPv6Teredo) return false;
            var b = ip.GetAddressBytes();
            if (b[0] == 0x20 && b[1] == 0x02) return false;                                       // 2002::/16 (6to4: lleva una IPv4 dentro)
            if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8) return false;       // 2001:db8::/32 (documentación)
            if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xFF && b[3] == 0x9B) return false;        // 64:ff9b::/96 (NAT64: lleva una IPv4 dentro)
            if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0 && b[4] == 0 && b[5] == 0 && b[6] == 0 && b[7] == 0 && b[8] == 0 && b[9] == 0 && b[10] == 0 && b[11] == 0)
                return false;                                                                     // ::a.b.c.d (compatible con IPv4)
            return true;
        }
        return false;
    }

    /// <summary>Valida la URL del manual (y de cada redirección). false = no se descarga.</summary>
    public static bool UrlPermitida(string? texto, out Uri? uri)
    {
        uri = null;
        if (string.IsNullOrWhiteSpace(texto) || texto.Length > MaxLongitudUrl) return false;
        if (!Uri.TryCreate(texto.Trim(), UriKind.Absolute, out var u)) return false;
        if (!PermitidaUri(u)) return false;
        uri = u;
        return true;
    }

    private static bool PermitidaUri(Uri u)
    {
        if (u.Scheme != Uri.UriSchemeHttps) return false;
        if (!string.IsNullOrEmpty(u.UserInfo)) return false;
        if (u.Port != 443) return false;
        var host = u.IdnHost.TrimEnd('.').ToLowerInvariant();
        if (host.Length == 0 || host == "localhost" || !host.Contains('.') && !host.Contains(':')) return false;
        if (SufijosInternos.Any(host.EndsWith)) return false;
        // Nombre de servidor que en realidad es una dirección IP: debe ser pública
        if (IPAddress.TryParse(host.Trim('[', ']'), out var ip)) return EsIpPublica(ip);
        return true;
    }

    /// <summary>Destino de una redirección (puede ser relativo): null si no es una URL permitida.</summary>
    public static Uri? ResolverRedireccion(Uri actual, Uri? ubicacion)
    {
        if (ubicacion is null) return null;
        var destino = ubicacion.IsAbsoluteUri ? ubicacion : new Uri(actual, ubicacion);
        return PermitidaUri(destino) ? destino : null;
    }

    /// <summary>
    /// Conexión del HttpClient de manuales: resuelve el nombre, exige que TODAS las direcciones sean públicas y conecta a una de las ya validadas.
    /// (SocketsHttpHandler.ConnectCallback; el TLS se negocia encima con el nombre original.)
    /// </summary>
    public static async ValueTask<Stream> ConectarAsync(SocketsHttpConnectionContext contexto, CancellationToken ct)
    {
        var host = contexto.DnsEndPoint.Host;
        var puerto = contexto.DnsEndPoint.Port;
        var direcciones = IPAddress.TryParse(host.Trim('[', ']'), out var literal) ? [literal] : await Dns.GetHostAddressesAsync(host, ct);
        if (direcciones.Length == 0 || !direcciones.All(EsIpPublica))
            throw new HttpRequestException("Destino no permitido.");

        Exception? ultimo = null;
        foreach (var ip in direcciones)
        {
            var socket = new Socket(ip.AddressFamily, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
            try
            {
                await socket.ConnectAsync(new IPEndPoint(ip, puerto), ct);
                return new NetworkStream(socket, ownsSocket: true);
            }
            catch (SocketException ex)
            {
                socket.Dispose();
                ultimo = ex;
            }
        }
        throw new HttpRequestException("No se pudo conectar con el servidor del manual.", ultimo);
    }
}
