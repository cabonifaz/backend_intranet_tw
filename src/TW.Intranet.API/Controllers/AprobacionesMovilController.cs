using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-31 — Centro de aprobaciones (el SP valida quién puede resolver salidas: encargado de su área según la RQ o supervisión general).</summary>
[ApiController]
[Authorize]
[Route("api/movil/aprobaciones")]
public class AprobacionesMovilController(
    ObtenerAprobacionesMovilCasoDeUso        obtener,
    ObtenerAprobacionSalidaMovilCasoDeUso    obtenerSalida,
    ResolverAprobacionSalidaMovilCasoDeUso   resolverSalida,
    ObtenerAprobacionLlegadaMovilCasoDeUso   obtenerLlegada,
    ResolverAprobacionLlegadaMovilCasoDeUso  resolverLlegada,
    ObtenerDetalleAprobacionMovilCasoDeUso   obtenerDetalle,
    ObtenerArchivoAprobacionMovilCasoDeUso   obtenerArchivo,
    ResolverAprobacionJefeMovilCasoDeUso     resolverJefe,
    RevisarGastoJefeMovilCasoDeUso           revisarGasto,
    ILogger<AprobacionesMovilController>     logger) : ControladorAppMovil(logger)
{
    /// <summary>Todo lo que espera la decisión del jefe (urgentes primero). El área sale de su cargo y de la RQ de cada servicio.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Solicitud de salida de una OS con el checklist del técnico, sus pendientes y su motivo.</summary>
    [HttpGet("salidas/{idOs:long}")]
    public async Task<IActionResult> ObtenerSalida(long idOs, CancellationToken ct)
        => Responder(await obtenerSalida.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>
    /// Autoriza (aprobar = true, con una condición) o rechaza (aprobar = false, con un motivo) la salida. El texto es obligatorio.
    /// El técnico recibe la notificación al instante y la decisión queda en la auditoría.
    /// </summary>
    [HttpPut("salidas/{idOs:long}")]
    public async Task<IActionResult> ResolverSalida(long idOs, [FromBody] ResolverAutorizacionSalidaDto dto, CancellationToken ct)
        => Responder(await resolverSalida.EjecutarAsync(IdUsuarioActual, idOs, dto, ct));

    /// <summary>Solicitud de llegada forzada de una OS (HU-06): dónde estaba el técnico, a cuántos metros de la planta y su motivo.</summary>
    [HttpGet("llegadas/{idOs:long}")]
    public async Task<IActionResult> ObtenerLlegada(long idOs, CancellationToken ct)
        => Responder(await obtenerLlegada.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Autoriza (con una condición) o rechaza (con un motivo) la llegada forzada. Solo después de aprobarla el técnico puede registrar su llegada.</summary>
    [HttpPut("llegadas/{idOs:long}")]
    public async Task<IActionResult> ResolverLlegada(long idOs, [FromBody] ResolverAutorizacionSalidaDto dto, CancellationToken ct)
        => Responder(await resolverLlegada.EjecutarAsync(IdUsuarioActual, idOs, dto, ct));

    // ── Evidencias forzadas (HU-12), ensayos con error (HU-10) y gastos (HU-27) ─────────────────

    /// <summary>Evidencia forzada: la toma, el motivo del técnico y lo que dijo la IA. Fotos: GET evidencias/{id}/archivo[?cuadro=true].</summary>
    [HttpGet("evidencias/{id:long}")]
    public async Task<IActionResult> ObtenerEvidencia(long id, CancellationToken ct)
        => Responder(await obtenerDetalle.EjecutarAsync(IdUsuarioActual, "evidencia", id, ct));

    /// <summary>Aprueba o rechaza la evidencia forzada: { aprobar, comentario } (comentario obligatorio al rechazar). Se notifica al técnico.</summary>
    [HttpPut("evidencias/{id:long}")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> ResolverEvidencia(long id, [FromBody] ResolverAutorizacionSalidaDto? dto, CancellationToken ct)
        => Responder(await resolverJefe.EjecutarAsync(IdUsuarioActual, "evidencia", id, dto, ct));

    /// <summary>Archivo de la evidencia (foto o video; con ?cuadro=true, la miniatura del video).</summary>
    [HttpGet("evidencias/{id:long}/archivo")]
    public async Task<IActionResult> ArchivoEvidencia(long id, [FromQuery] bool cuadro, CancellationToken ct)
        => Archivo(await obtenerArchivo.EjecutarAsync(IdUsuarioActual, "evidencia", id, 1, cuadro, ct));

    /// <summary>Ensayo guardado con error crítico: motivo del técnico y lecturas fuera del EMP.</summary>
    [HttpGet("ensayos/{id:long}")]
    public async Task<IActionResult> ObtenerEnsayo(long id, CancellationToken ct)
        => Responder(await obtenerDetalle.EjecutarAsync(IdUsuarioActual, "ensayo", id, ct));

    /// <summary>Aprueba o rechaza el ensayo con error: { aprobar, comentario } (comentario obligatorio al rechazar). Se notifica al técnico.</summary>
    [HttpPut("ensayos/{id:long}")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> ResolverEnsayo(long id, [FromBody] ResolverAutorizacionSalidaDto? dto, CancellationToken ct)
        => Responder(await resolverJefe.EjecutarAsync(IdUsuarioActual, "ensayo", id, dto, ct));

    /// <summary>Gasto rendido: monto, origen, reparto, fotos, motivo sin foto y lectura de la IA. Fotos: GET gastos/{id}/fotos/{n}.</summary>
    [HttpGet("gastos/{id:long}")]
    public async Task<IActionResult> ObtenerGasto(long id, CancellationToken ct)
        => Responder(await obtenerDetalle.EjecutarAsync(IdUsuarioActual, "gasto", id, ct));

    /// <summary>
    /// Aprueba, observa o rechaza el gasto: { accion: aprobar | observar | rechazar, comentario } (comentario obligatorio al observar o rechazar).
    /// Solo el Jefe de Operaciones. Se notifica al técnico y queda en la auditoría.
    /// </summary>
    [HttpPut("gastos/{id:long}")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> RevisarGasto(long id, [FromBody] RevisarGastoDto? dto, CancellationToken ct)
        => Responder(await revisarGasto.EjecutarAsync(IdUsuarioActual, id, dto, ct));

    /// <summary>Foto n (1 a 5) del gasto.</summary>
    [HttpGet("gastos/{id:long}/fotos/{n:int}")]
    public async Task<IActionResult> FotoGasto(long id, int n, CancellationToken ct)
        => Archivo(await obtenerArchivo.EjecutarAsync(IdUsuarioActual, "gasto", id, n, false, ct));

    private IActionResult Archivo((Stream? Contenido, string? Tipo, string? Mensaje) a)
    {
        if (a.Contenido is null) return NotFound(new RespuestaDto<object>(1, a.Mensaje ?? "Archivo no encontrado."));
        Response.Headers.CacheControl = "private, no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return File(a.Contenido, a.Tipo!, enableRangeProcessing: true);
    }
}
