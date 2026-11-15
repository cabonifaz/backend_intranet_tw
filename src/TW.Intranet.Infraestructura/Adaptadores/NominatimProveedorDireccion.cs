using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Dirección legible por coordenadas con Nominatim (OpenStreetMap), gratuito y sin llave. Solo se envían coordenadas.
/// Política de Nominatim: máximo 1 consulta por segundo y User-Agent que identifique la app → las consultas se ponen en fila (una por segundo, para toda la API)
/// y cada respuesta se guarda en memoria 1 día por punto redondeado a ~11 m. Si no responde a tiempo (2 s por defecto) devuelve null: el ubigeo es lo importante.
/// </summary>
public class NominatimProveedorDireccion(HttpClient http, ConfiguracionNominatim configuracion) : IProveedorDireccion
{
    private readonly string _url = configuracion.Url.TrimEnd('/');
    private readonly TimeSpan _tiempoMaximo = TimeSpan.FromMilliseconds(Math.Clamp(configuracion.TiempoMaximoMs, 500, 5000));

    private static readonly ConcurrentDictionary<string, (DateTime Hasta, string? Valor)> Cache = new();
    private static readonly SemaphoreSlim Fila = new(1, 1);
    private static DateTime _ultimaConsulta = DateTime.MinValue;

    private static string N(decimal v, int dec) => Math.Round(v, dec).ToString(CultureInfo.InvariantCulture);

    public async Task<string?> ObtenerDireccionAsync(decimal latitud, decimal longitud, CancellationToken ct)
    {
        if (!configuracion.Habilitado) return null;

        var clave = $"{N(latitud, 4)},{N(longitud, 4)}";
        if (Cache.TryGetValue(clave, out var e) && e.Hasta > DateTime.UtcNow) return e.Valor;

        using var tiempo = CancellationTokenSource.CreateLinkedTokenSource(ct);
        tiempo.CancelAfter(_tiempoMaximo);
        var entro = false;
        try
        {
            await Fila.WaitAsync(tiempo.Token);
            entro = true;

            // Otra petición pudo resolver el mismo punto mientras esperaba en la fila
            if (Cache.TryGetValue(clave, out e) && e.Hasta > DateTime.UtcNow) return e.Valor;

            var espera = _ultimaConsulta.AddSeconds(1) - DateTime.UtcNow;
            if (espera > TimeSpan.Zero) await Task.Delay(espera, tiempo.Token);
            _ultimaConsulta = DateTime.UtcNow;

            var url = $"{_url}/reverse?format=json&lat={N(latitud, 6)}&lon={N(longitud, 6)}&zoom=18&addressdetails=1&accept-language=es";
            using var pedido = new HttpRequestMessage(HttpMethod.Get, url);
            pedido.Headers.UserAgent.ParseAdd(configuracion.UserAgent);
            using var resp = await http.SendAsync(pedido, tiempo.Token);
            if (!resp.IsSuccessStatusCode) return Recordar(clave, null, TimeSpan.FromSeconds(30));

            using var doc = await JsonDocument.ParseAsync(await resp.Content.ReadAsStreamAsync(tiempo.Token), cancellationToken: tiempo.Token);
            var direccion = doc.RootElement.TryGetProperty("address", out var address) ? ArmarDireccion(address) : null;
            return Recordar(clave, direccion, TimeSpan.FromDays(1));
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return null; // sin servicio o sin tiempo: la dirección sale null y el endpoint sigue
        }
        finally
        {
            if (entro) Fila.Release();
        }
    }

    private static string? Recordar(string clave, string? valor, TimeSpan vida)
    {
        if (Cache.Count > 5000) foreach (var k in Cache.Where(x => x.Value.Hasta <= DateTime.UtcNow).Select(x => x.Key).ToList()) Cache.TryRemove(k, out _);
        Cache[clave] = (DateTime.UtcNow + vida, valor);
        return valor;
    }

    /// <summary>"{calle} {número}" si hay calle; si no, barrio → urbanización → caserío → pueblo; si nada, null. No repite distrito, provincia ni país.</summary>
    public static string? ArmarDireccion(JsonElement address)
    {
        string? Campo(string nombre) =>
            address.ValueKind == JsonValueKind.Object && address.TryGetProperty(nombre, out var v) && v.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(v.GetString()) ? v.GetString()!.Trim() : null;

        var calle = Campo("road");
        if (calle is not null)
        {
            var numero = Campo("house_number");
            return Recortar(numero is null ? calle : $"{calle} {numero}");
        }
        var zona = Campo("neighbourhood") ?? Campo("suburb") ?? Campo("hamlet") ?? Campo("village");
        return zona is null ? null : Recortar(zona);
    }

    // direccion_exacta admite 500 caracteres
    private static string Recortar(string texto) => texto.Length <= 500 ? texto : texto[..500];
}
