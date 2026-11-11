using System.Net;
using System.Security.Cryptography;
using System.Text;

using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Lee los PDF oficiales que se le dan al Asistente IA (App Mobile HU-19):
///  - procedimiento aprobado: la ruta interna del almacenamiento (la misma que sirve la intranet);
///  - manual del suministro: se descarga por https con las guardas de GuardaUrlManual (anti-SSRF), tope de 15 MB, tiempo máximo y comprobación de que sea un PDF;
///    se guarda en caché en el almacenamiento (asistente-cache/{hash de la URL}-{aaaammdd}.pdf) y se reutiliza durante 7 días.
/// Un documento que no se puede leer no frena a los demás: queda con su motivo en `Error`.
/// </summary>
public class DocumentosAsistente(IAlmacenArchivos almacen, HttpClient http) : IDocumentosAsistente
{
    public const long MaxBytesPorDocumento = 15L * 1024 * 1024;
    public const int DiasCache = 7;

    /// <summary>Todo PDF empieza con "%PDF-" (se tolera algo de basura antes, como hacen los lectores de PDF).</summary>
    public static bool EsPdf(ReadOnlySpan<byte> bytes)
    {
        ReadOnlySpan<byte> firma = "%PDF-"u8;
        return bytes.Length >= 5 && bytes[..Math.Min(bytes.Length, 1024)].IndexOf(firma) >= 0;
    }

    /// <summary>Ruta de caché del manual de una URL en una fecha: asistente-cache/{sha256 de la URL}-{aaaammdd}.pdf</summary>
    public static string RutaCache(string url, DateTime fechaUtc) =>
        $"asistente-cache/{Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(url))).ToLowerInvariant()}-{fechaUtc:yyyyMMdd}.pdf";

    public VerificacionCitaAsistente Verificar(byte[] pdf, int? pagina, string fragmento) => VerificadorCitasPdf.Verificar(pdf, pagina, fragmento);

    public async Task<IReadOnlyList<DocumentoCargadoAsistente>> CargarAsync(IReadOnlyList<DocumentoAsistenteMovil> documentos, CancellationToken ct)
    {
        var tareas = documentos.Select(d => CargarUnoAsync(d, ct)).ToArray();
        return await Task.WhenAll(tareas);
    }

    private async Task<DocumentoCargadoAsistente> CargarUnoAsync(DocumentoAsistenteMovil d, CancellationToken ct)
    {
        try
        {
            var (pdf, error) = d.Tipo == "procedimiento" ? await LeerProcedimientoAsync(d.Ubicacion, ct) : await LeerManualAsync(d.Ubicacion, ct);
            return new DocumentoCargadoAsistente(d, pdf, error);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception)
        {
            return new DocumentoCargadoAsistente(d, null, "No se pudo leer el documento.");
        }
    }

    private async Task<(byte[]? Pdf, string? Error)> LeerProcedimientoAsync(string ruta, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(ruta)) return (null, "El procedimiento no tiene PDF.");
        await using var s = await almacen.AbrirLecturaAsync(ruta, ct);
        if (s is null) return (null, "El PDF del procedimiento ya no está disponible.");
        return await LeerAcotadoAsync(s, ct);
    }

    private static async Task<(byte[]? Pdf, string? Error)> LeerAcotadoAsync(Stream s, CancellationToken ct)
    {
        using var m = new MemoryStream();
        var buffer = new byte[81920];
        int leidos;
        while ((leidos = await s.ReadAsync(buffer, ct)) > 0)
        {
            if (m.Length + leidos > MaxBytesPorDocumento) return (null, "El PDF supera el tamaño permitido.");
            m.Write(buffer, 0, leidos);
        }
        var bytes = m.ToArray();
        return EsPdf(bytes) ? (bytes, null) : (null, "El archivo no es un PDF.");
    }

    private async Task<(byte[]? Pdf, string? Error)> LeerManualAsync(string url, CancellationToken ct)
    {
        if (!GuardaUrlManual.UrlPermitida(url, out var uri) || uri is null) return (null, "La URL del manual no es válida.");
        var normalizada = uri.AbsoluteUri;

        // Caché: la descarga de los últimos 7 días
        var hoy = DateTime.UtcNow;
        for (var dia = 0; dia < DiasCache; dia++)
        {
            await using var cache = await almacen.AbrirLecturaAsync(RutaCache(normalizada, hoy.AddDays(-dia)), ct);
            if (cache is null) continue;
            var (pdfCache, _) = await LeerAcotadoAsync(cache, ct);
            if (pdfCache is not null) return (pdfCache, null);
        }

        var (pdf, error) = await DescargarAsync(uri, ct);
        if (pdf is null) return (null, error);

        try
        {
            await almacen.GuardarAsync(RutaCache(normalizada, hoy), new MemoryStream(pdf), ct);
            // Limpieza: lo que ya pasó de la vigencia (una semana más)
            for (var dia = DiasCache; dia < DiasCache * 2; dia++) await almacen.EliminarAsync(RutaCache(normalizada, hoy.AddDays(-dia)), ct);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or UnauthorizedAccessException)
        {
            // la caché es solo una ayuda: si no se pudo guardar (p. ej. dos consultas a la vez), se sigue
        }
        return (pdf, null);
    }

    private async Task<(byte[]? Pdf, string? Error)> DescargarAsync(Uri inicio, CancellationToken ct)
    {
        var actual = inicio;
        for (var salto = 0; salto <= GuardaUrlManual.MaxRedirecciones; salto++)
        {
            using var solicitud = new HttpRequestMessage(HttpMethod.Get, actual);
            solicitud.Headers.Accept.ParseAdd("application/pdf, */*;q=0.5");
            using var respuesta = await http.SendAsync(solicitud, HttpCompletionOption.ResponseHeadersRead, ct);

            if (respuesta.StatusCode is HttpStatusCode.Moved or HttpStatusCode.Redirect or HttpStatusCode.RedirectMethod or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
            {
                var destino = GuardaUrlManual.ResolverRedireccion(actual, respuesta.Headers.Location);
                if (destino is null) return (null, "El manual redirige a un destino no permitido.");
                actual = destino;
                continue;
            }
            if (!respuesta.IsSuccessStatusCode) return (null, $"El servidor del manual respondió {(int)respuesta.StatusCode}.");
            if (respuesta.Content.Headers.ContentLength > MaxBytesPorDocumento) return (null, "El manual supera el tamaño permitido.");

            await using var cuerpo = await respuesta.Content.ReadAsStreamAsync(ct);
            return await LeerAcotadoAsync(cuerpo, ct);
        }
        return (null, "El manual tiene demasiadas redirecciones.");
    }
}
