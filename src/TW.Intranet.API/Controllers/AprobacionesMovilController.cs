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
}
