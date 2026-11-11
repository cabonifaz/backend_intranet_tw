using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-15 / HU-16 — Cabecera del informe (Datos · Detalle Serv. · Observación y pruebas) y Hard Stop de cierre del trabajo en el equipo.</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/equipos/{idOsEquipo:long}")]
public class InformeEquipoMovilController(
    ObtenerCabeceraInformeMovilCasoDeUso    obtener,
    GuardarCabeceraInformeMovilCasoDeUso    guardar,
    SubirFotoFallaMovilCasoDeUso            subirFoto,
    ValidarCierreEquipoMovilCasoDeUso       validarCierre,
    GenerarInformeEquipoMovilCasoDeUso      generar,
    ILogger<InformeEquipoMovilController>   logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoPeticionFoto = 8 * 1024 * 1024;

    /// <summary>Formulario multipart de la foto de una falla. Los números llegan como texto con punto decimal.</summary>
    public class FotoFallaFormulario
    {
        public string? Latitud         { get; set; }
        public string? Longitud        { get; set; }
        public string? PrecisionMetros { get; set; }
        /// <summary>Hora (ISO 8601, UTC) en que el teléfono tomó la foto.</summary>
        public string? CapturadoEn     { get; set; }
        /// <summary>Foto JPEG de la cámara de la app.</summary>
        public IFormFile? Archivo      { get; set; }
    }

    /// <summary>Las 3 pestañas de la cabecera del informe. Exige la llegada registrada y el equipo iniciado.</summary>
    [HttpGet("cabecera-informe")]
    public async Task<IActionResult> Obtener(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>
    /// Guarda las secciones de la cabecera que vienen (una sección ausente no se toca). Cada falla exige una prueba que la justifique: el servidor calcula E, el EMP y la
    /// conformidad. Devuelve la cabecera actualizada. Solo con el equipo en ejecución y el informe sin generar.
    /// </summary>
    [HttpPut("cabecera-informe")]
    [RequestSizeLimit(64 * 1024)]
    public async Task<IActionResult> Guardar(long idOs, long idOsEquipo, [FromBody] GuardarCabeceraInformeMovilDto? d, CancellationToken ct)
        => Responder(await guardar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Foto de una falla (JPEG de la cámara de la app). Devuelve su id: se envía en "fotos" de la falla al guardar la cabecera. Se ve con /evidencias/{id}/archivo.</summary>
    [HttpPost("cabecera-informe/fotos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticionFoto)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticionFoto)]
    public async Task<IActionResult> SubirFoto(long idOs, long idOsEquipo, [FromForm] FotoFallaFormulario f, CancellationToken ct)
    {
        await using var a = f.Archivo?.OpenReadStream();
        return Responder(await subirFoto.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, a, f.Archivo?.Length ?? 0, Decimal(f.Latitud), Decimal(f.Longitud), Decimal(f.PrecisionMetros),
            FechaUtc(f.CapturadoEn), ct));
    }

    /// <summary>HU-16 · Hard Stop: valida las 5 etapas al tocar "Finalizar trabajo en equipo" y devuelve la validación completa o los pendientes por etapa. No escribe nada.</summary>
    [HttpGet("cierre")]
    public async Task<IActionResult> ValidarCierre(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await validarCierre.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>HU-16: con las 5 etapas conformes genera el informe técnico (N° NNNN-AAAA) y deja el equipo completado. Repetirlo devuelve el mismo informe. Sigue Firma de informes (HU-17).</summary>
    [HttpPost("informe")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> Generar(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await generar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    private static DateTime? FechaUtc(string? texto) =>
        texto is { Length: <= 40 }
        && DateTimeOffset.TryParse(texto, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var x)
            ? DateTime.SpecifyKind(x.UtcDateTime, DateTimeKind.Unspecified)
            : null;

    private static decimal? Decimal(string? texto) =>
        decimal.TryParse(texto, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : null;
}
