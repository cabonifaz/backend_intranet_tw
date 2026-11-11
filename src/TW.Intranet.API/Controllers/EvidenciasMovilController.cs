using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-11 / HU-12 / HU-13 — Registro fotográfico con validación IA, evidencia forzada y microvideo de encendido.</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/equipos/{idOsEquipo:long}/evidencias")]
public class EvidenciasMovilController(
    ObtenerEvidenciasMovilCasoDeUso          obtener,
    RegistrarEvidenciaMovilCasoDeUso         registrar,
    ForzarEvidenciaMovilCasoDeUso            forzar,
    ObtenerArchivoEvidenciaMovilCasoDeUso    archivo,
    ILogger<EvidenciasMovilController>       logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoPeticion = 24 * 1024 * 1024;

    /// <summary>Formulario multipart de una captura. Los números llegan como texto con punto decimal.</summary>
    public class CapturaEvidenciaFormulario
    {
        public string? Codigo      { get; set; }
        public int?    Pagina      { get; set; }
        public string? Latitud     { get; set; }
        public string? Longitud    { get; set; }
        public string? PrecisionMetros { get; set; }
        /// <summary>Hora (ISO 8601, UTC) en que el teléfono tomó la captura.</summary>
        public string? CapturadoEn { get; set; }
        public string? DuracionSeg { get; set; }
        /// <summary>Contenido leído del QR (solo evidencia "qr").</summary>
        public string? QrTexto     { get; set; }
        /// <summary>Foto JPEG, o el video MP4 del encendido.</summary>
        public IFormFile? Archivo  { get; set; }
        /// <summary>Cuadro JPEG del video (lo analiza la IA y sirve de miniatura).</summary>
        public IFormFile? Cuadro   { get; set; }
    }

    /// <summary>Panel de las 9 evidencias con su estado, el avance y lo de "Ver detalles" de las forzadas. Exige la llegada registrada y el equipo iniciado.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>
    /// Captura una evidencia (foto JPEG de la cámara, microvideo MP4 de 3 a 5 s para el encendido, o el texto leído del QR). Se valida con IA y se registra el
    /// intento; una toma rechazada se conserva para poder forzarla.
    /// </summary>
    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Registrar(long idOs, long idOsEquipo, [FromForm] CapturaEvidenciaFormulario f, CancellationToken ct)
    {
        var dto = new CapturaEvidenciaMovilDto(f.Codigo, f.Pagina ?? 1, Decimal(f.Latitud), Decimal(f.Longitud), Decimal(f.PrecisionMetros), FechaUtc(f.CapturadoEn),
            Decimal(f.DuracionSeg), f.QrTexto);
        await using var a = f.Archivo?.OpenReadStream();
        await using var c = f.Cuadro?.OpenReadStream();
        return Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, dto, a, f.Archivo?.Length ?? 0, c, f.Cuadro?.Length ?? 0, ct));
    }

    /// <summary>HU-12: acepta a la fuerza una foto rechazada por la IA, solo con un motivo escrito. Queda como excepción y visible para Jefatura. Devuelve el panel actualizado.</summary>
    [HttpPost("{idEvidencia:long}/forzar")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> Forzar(long idOs, long idOsEquipo, long idEvidencia, [FromBody] PeticionForzarEvidenciaMovilDto? d, CancellationToken ct)
        => Responder(await forzar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, idEvidencia, d, ct));

    /// <summary>El archivo de una evidencia (foto, video o, con ?cuadro=true, el cuadro del video). Solo de una OS del técnico.</summary>
    [HttpGet("{idEvidencia:long}/archivo")]
    public async Task<IActionResult> Archivo(long idOs, long idOsEquipo, long idEvidencia, [FromQuery] bool cuadro, CancellationToken ct)
    {
        var (contenido, tipo, mensaje) = await archivo.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, idEvidencia, cuadro, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Evidencia no encontrada.")) : File(contenido, tipo!, enableRangeProcessing: true);
    }

    private static DateTime? FechaUtc(string? texto) =>
        texto is { Length: <= 40 }
        && DateTimeOffset.TryParse(texto, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var x)
            ? DateTime.SpecifyKind(x.UtcDateTime, DateTimeKind.Unspecified)
            : null;

    private static decimal? Decimal(string? texto) =>
        decimal.TryParse(texto, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : null;
}
