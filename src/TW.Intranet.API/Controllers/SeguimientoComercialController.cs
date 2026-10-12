using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-17 Bandeja · HU-18 Detalle del Seguimiento Comercial (propuestas enviadas al cliente).</summary>
[ApiController]
[Authorize]
public class SeguimientoComercialController(
    ObtenerBandejaSeguimientoCasoDeUso obtenerBandeja,
    ObtenerDetalleSeguimientoCasoDeUso obtenerDetalle) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>
    /// HU-17 — KPIs del pipeline, listado con días transcurridos, próxima acción y estado del SLA,
    /// y opciones del filtro de responsable (tal cual vienen de las propuestas en alcance).
    /// ?idResponsable=&amp;estado=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_bandeja")]
    [HttpGet("api/crm/seguimiento")]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaSeguimientoDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>
    /// HU-18 — Detalle del seguimiento de una propuesta: panel superior (monto, días, SLA restante),
    /// próxima acción, timeline de interacciones, próximas acciones, contactos, documentos
    /// y permisos de los botones (registrar seguimiento, aceptación y rechazo).
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_bandeja")]
    [HttpGet("api/crm/seguimiento/{idPropuesta:long}")]
    public async Task<IActionResult> Detalle(long idPropuesta, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));
}
