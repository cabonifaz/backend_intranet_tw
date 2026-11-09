using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// CRM › Propuestas › pestaña "Precotizaciones Técnicas" (Sprint 5, HU-60). Comercial ve las precotizaciones que generó Servicio
/// Técnico al revisar los informes y las convierte en propuesta con la información precargada y asociada al RQ de origen.
/// Flujo: GET /{id}/propuesta (precarga) → el front crea la propuesta con POST /api/crm/propuestas → POST /{id}/convertir.
/// Permisos: precot_ver, precot_convertir. Alcance por usuario y rol igual que el resto del CRM (responsable del RQ).
/// </summary>
[ApiController]
[Route("api/crm/precotizaciones")]
[Authorize]
public class PrecotizacionesController(
    ObtenerBandejaPrecotizacionesCasoDeUso bandeja,
    ObtenerDetallePrecotizacionCasoDeUso   detalle,
    ObtenerPrecargaPrecotizacionCasoDeUso  precarga,
    ConvertirPrecotizacionCasoDeUso        convertir,
    ILogger<PrecotizacionesController>     logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Precotizaciones: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo completar la operación. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>Bandeja con tarjetas. Query: estado (todas · pendiente · convertida), busqueda, idSupervisor, fechaDesde, fechaHasta, pagina, porPagina.</summary>
    [RequierePermiso("precot_ver")]
    [HttpGet]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosPrecotizacionesDto filtros, CancellationToken ct = default)
        => Responder(await bandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>Modal "Detalle de Precotización Técnica": datos, observaciones, ítems, trazabilidad y propuesta derivada.</summary>
    [RequierePermiso("precot_ver")]
    [HttpGet("{idPrecotizacion:long}")]
    public async Task<IActionResult> Detalle(long idPrecotizacion, CancellationToken ct = default)
        => Responder(await detalle.EjecutarAsync(idPrecotizacion, IdUsuarioActual, ct));

    /// <summary>"Generar Propuesta Comercial": RQ, cliente, contacto, nota del supervisor e ítems a inyectar en la nueva propuesta.</summary>
    [RequierePermiso("precot_convertir")]
    [HttpGet("{idPrecotizacion:long}/propuesta")]
    public async Task<IActionResult> Precarga(long idPrecotizacion, CancellationToken ct = default)
        => Responder(await precarga.EjecutarAsync(idPrecotizacion, IdUsuarioActual, ct));

    /// <summary>Marca la precotización como convertida en la propuesta recién creada. Body: { idPropuesta }.</summary>
    [RequierePermiso("precot_convertir")]
    [HttpPost("{idPrecotizacion:long}/convertir")]
    public async Task<IActionResult> Convertir(long idPrecotizacion, [FromBody] ConvertirPrecotizacionDto datos, CancellationToken ct = default)
        => Responder(await convertir.EjecutarAsync(idPrecotizacion, datos, IdUsuarioActual, ct));
}
