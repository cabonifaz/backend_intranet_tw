using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-53 (Sprint 5) Pestaña "Registrar" del detalle del servicio en ruta: el Asistente de Seguimiento registra, en nombre del técnico, una observación,
/// una demora/incidente o (crítico) un cambio manual de estado cuando el técnico no puede usar su app móvil.
/// GET formulario: seg_bandeja. POST registro: seg_registrar (cada SP vuelve a validar el permiso). Solo servicios de la jornada de hoy.
/// Cada registro queda auditado (nombre completo, fecha-hora y modo) y se ve en el Timeline (HU-52) y en el historial del expediente.
/// </summary>
[ApiController]
[Route("api/operaciones/seguimiento/servicios/{idOs:long}/registros")]
[Authorize]
public class RegistroAsistenteController(
    ObtenerFormularioRegistroAsistenteCasoDeUso formulario,
    RegistrarAsistenteServicioRutaCasoDeUso     registrar,
    SubirEvidenciaSeguimientoCasoDeUso          subirEvidencia,
    ILogger<RegistroAsistenteController> logger) : ControllerBase
{
    private const int TamanoMaximoPeticion = 16 * 1024;
    // Foto de 5 MB + cabeceras del multipart
    private const long TamanoMaximoEvidencia = EvidenciaSeguimiento.TamanoMaximoBytes + 64 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400. Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        // Datos de seguimiento operativo: sin sniffing de tipo y sin caché en el navegador ni en intermediarios
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["Cache-Control"] = "no-store";
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Registro del asistente: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo completar la operación. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>Formulario: "Registrando como", hora actual, estado actual, catálogos, eventos vinculables y "Mis registros de hoy".</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Formulario(long idOs, CancellationToken ct = default)
        => Responder(await formulario.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Registra una observación, demora/incidente o cambio manual de estado (campo modo: observacion | demora | cambio_estado).</summary>
    [RequierePermiso("seg_registrar")]
    [HttpPost]
    [Consumes("application/json")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    public async Task<IActionResult> Registrar(long idOs, [FromBody] RegistrarAsistenteSolicitudDto? solicitud, CancellationToken ct = default)
        => Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, solicitud, ct));

    /// <summary>
    /// Sube la foto de evidencia (Modo 2 Demora/Incidente). multipart/form-data, campo "archivo": JPG, PNG o WEBP de hasta 5 MB.
    /// Devuelve datos.url, que se envía tal cual como evidenciaUrl en POST /registros.
    /// </summary>
    [RequierePermiso("seg_registrar")]
    [HttpPost("evidencia")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoEvidencia)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoEvidencia)]
    public async Task<IActionResult> SubirEvidencia(long idOs, IFormFile? archivo, CancellationToken ct = default)
    {
        await using var contenido = archivo?.OpenReadStream();
        return Responder(await subirEvidencia.EjecutarAsync(IdUsuarioActual, idOs, contenido, archivo?.Length ?? 0, archivo?.FileName, ct));
    }
}
