using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Módulo Órdenes de Servicio / Metrología (OS / OM), Sprint 4. Las órdenes nacen de una propuesta aceptada
/// (HU-40); esta bandeja no crea órdenes.
/// Acceso: os_bandeja (Comercial) u os_bandeja_operaciones (Operaciones, consulta).
/// </summary>
[ApiController]
[Route("api/crm/ordenes-servicio")]
[Authorize]
public class OrdenesServicioController(
    ObtenerBandejaOrdenesServicioCasoDeUso  obtenerBandeja,
    ExportarBandejaOrdenesServicioCasoDeUso exportarBandeja) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) => r.IdTipoMensaje switch
    {
        2 => Ok(r),
        1 => BadRequest(r),
        _ => StatusCode(500, r),
    };

    /// <summary>
    /// HU-41 Bandeja: tarjetas por estado, filas, total y opciones de filtro (clientes y responsables).
    /// ?estado=todas|borrador|emitida|programada|en_ejecucion|finalizada|anulada &amp;tipo=OS|OM
    /// &amp;idCliente=&amp;idResponsable=&amp;fechaDesde=&amp;fechaHasta=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// </summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaOrdenesServicioDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>HU-41 Exportar XLSX con los mismos filtros de la bandeja (todas las filas).</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("exportar")]
    public async Task<IActionResult> Exportar([FromQuery] FiltrosBandejaOrdenesServicioDto filtros, CancellationToken ct = default)
    {
        var r = await exportarBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }
}
