using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-05 — Registro de demoras en ruta (llegar a planta / ingreso a planta).</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/demoras")]
public class DemorasMovilController(
    ObtenerDemorasMovilCasoDeUso    obtener,
    RegistrarDemoraMovilCasoDeUso   registrar,
    ILogger<DemorasMovilController> logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoPeticion = 6 * 1024 * 1024;

    /// <summary>Formulario multipart de la app. Los números llegan como texto con punto decimal (no depende de la cultura del servidor).</summary>
    public class RegistrarDemoraFormulario
    {
        public string? Tipo { get; set; }
        public int IdMotivo { get; set; }
        public int DuracionMinutos { get; set; }
        public string? Descripcion { get; set; }
        public string? Latitud { get; set; }
        public string? Longitud { get; set; }
        public string? PrecisionMetros { get; set; }
        /// <summary>Hora en que el teléfono registró la demora (ISO 8601, UTC). Si no hay conexión, la app la envía después con esa hora.</summary>
        public string? CapturadoEn { get; set; }
        public IFormFile? Foto { get; set; }
    }

    /// <summary>
    /// Contexto de la pantalla: qué tipos de demora se pueden registrar ahora, las horas (ETA original, vigente, inicio previsto),
    /// los tipos del catálogo y las demoras ya registradas. La OS debe ser del técnico del token.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(long idOs, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>
    /// Registra una demora. GPS y hora se capturan solos (la hora la pone el servidor); la foto es opcional y solo JPEG de la cámara.
    /// Avisa a Operaciones y recalcula la ETA de llegada (tipo llegada) o el inicio del trabajo (tipo ingreso).
    /// </summary>
    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Registrar(long idOs, [FromForm] RegistrarDemoraFormulario f, CancellationToken ct)
    {
        var dto = new NuevaDemoraMovilDto(
            f.Tipo, f.IdMotivo, f.DuracionMinutos, f.Descripcion,
            Decimal(f.Latitud), Decimal(f.Longitud), Decimal(f.PrecisionMetros), FechaUtc(f.CapturadoEn));

        await using var contenido = f.Foto?.OpenReadStream();
        return Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, dto, contenido, f.Foto?.Length ?? 0, ct));
    }

    /// <summary>ISO 8601 con zona ("2026-11-06T17:43:10.000Z") → UTC; sin zona se toma como UTC. Texto inválido = null (vale la hora del servidor).</summary>
    private static DateTime? FechaUtc(string? texto) =>
        texto is { Length: <= 40 }
        && DateTimeOffset.TryParse(texto, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var f)
            ? f.UtcDateTime
            : null;

    private static decimal? Decimal(string? texto) =>
        decimal.TryParse(texto, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : null;
}
