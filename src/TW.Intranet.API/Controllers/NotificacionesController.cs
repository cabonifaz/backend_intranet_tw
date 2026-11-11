using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Notificaciones del usuario autenticado. HU-90 Centro de Notificaciones (Sprint 5, Módulo 16): campana del header + bandeja
/// completa /notificaciones. Módulo transversal: lo usan todos los usuarios de la intranet, por eso no lleva [RequierePermiso];
/// la seguridad está en que cada SP filtra por el usuario del token (una notificación ajena responde "no encontrada").
/// El token de la app móvil no entra aquí (la app tiene api/movil/notificaciones).
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class NotificacionesController(
    ObtenerNotificacionesCasoDeUso           casoDeUso,
    ObtenerResumenNotificacionesCasoDeUso    resumen,
    ObtenerBandejaNotificacionesCasoDeUso    bandeja,
    ObtenerDetalleNotificacionCasoDeUso      detalle,
    MarcarNotificacionesLeidasCasoDeUso      marcarLeidas,
    ArchivarNotificacionCasoDeUso            archivar,
    ObtenerFiltrosNotificacionesCasoDeUso    filtros,
    ILogger<NotificacionesController>        logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400. Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Notificaciones: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo completar la operación. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>Topbar actual: las 20 notificaciones más recientes (sin cambios; se mantiene mientras el front migra a /resumen).</summary>
    [HttpGet]
    public async Task<IActionResult> ObtenerNotificaciones(CancellationToken ct)
    {
        if (IdUsuarioActual <= 0)
            return Unauthorized();

        var respuesta = await casoDeUso.EjecutarAsync(IdUsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>HU-90 Campana: badge (no leídas) + popover con las 5 últimas no leídas.</summary>
    [HttpGet("resumen")]
    public async Task<IActionResult> Resumen(CancellationToken ct = default)
        => Responder(await resumen.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>HU-90 Bandeja completa. Query: estado, modulos (coma), tipos (coma), rango, fechaDesde, fechaHasta,
    /// remitente (0 = Sistema), busqueda, pagina, porPagina.</summary>
    [HttpGet("bandeja")]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaNotificacionesDto f, CancellationToken ct = default)
        => Responder(await bandeja.EjecutarAsync(f, IdUsuarioActual, ct));

    /// <summary>HU-90 Opciones de los filtros (módulos y tipos con conteos, estados, rangos y remitentes).</summary>
    [HttpGet("filtros")]
    public async Task<IActionResult> Filtros(CancellationToken ct = default)
        => Responder(await filtros.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>HU-90 Panel de detalle. Al abrirla queda LEÍDA (lo pide la HU).</summary>
    [HttpGet("{idNotificacion:long}")]
    public async Task<IActionResult> Detalle(long idNotificacion, CancellationToken ct = default)
        => Responder(await detalle.EjecutarAsync(idNotificacion, IdUsuarioActual, ct));

    /// <summary>HU-90 "Marcar las 5 como leídas" → { "ids": [..] } · "Marcar todas como leídas" → { "todas": true }.</summary>
    [HttpPost("marcar-leidas")]
    public async Task<IActionResult> MarcarLeidas([FromBody] MarcarNotificacionesLeidasDto? datos, CancellationToken ct = default)
        => Responder(await marcarLeidas.EjecutarAsync(datos, IdUsuarioActual, ct));

    /// <summary>HU-90 "Archivar" (solo si está leída).</summary>
    [HttpPost("{idNotificacion:long}/archivar")]
    public async Task<IActionResult> Archivar(long idNotificacion, CancellationToken ct = default)
        => Responder(await archivar.EjecutarAsync(idNotificacion, IdUsuarioActual, ct));
}
