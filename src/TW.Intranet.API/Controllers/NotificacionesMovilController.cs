using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-02 / HU-04 — Notificaciones del usuario (autorizaciones de salida, servicios, gastos, demoras…).</summary>
[ApiController]
[Authorize]
[Route("api/movil/notificaciones")]
public class NotificacionesMovilController(
    ObtenerNotificacionesMovilCasoDeUso  obtener,
    MarcarNotificacionMovilCasoDeUso     marcar,
    ILogger<NotificacionesMovilController> logger) : ControladorAppMovil(logger)
{
    /// <summary>Las 60 notificaciones más recientes del usuario que inició sesión (sale del token).</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Marca una notificación como leída. Solo las propias: una ajena responde como inexistente.</summary>
    [HttpPut("{idNotificacion:long}/leida")]
    public async Task<IActionResult> MarcarLeida(long idNotificacion, CancellationToken ct)
        => Responder(await marcar.EjecutarAsync(IdUsuarioActual, idNotificacion, ct));

    /// <summary>Marca todas las notificaciones no leídas del usuario.</summary>
    [HttpPut("leidas")]
    public async Task<IActionResult> MarcarTodasLeidas(CancellationToken ct)
        => Responder(await marcar.EjecutarAsync(IdUsuarioActual, 0, ct));
}
