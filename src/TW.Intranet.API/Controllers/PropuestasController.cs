using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-07 / HU-08 / HU-09 / HU-10 — Propuestas comerciales.</summary>
[ApiController]
[Route("api/crm/propuestas")]
[Authorize]
public class PropuestasController(
    ObtenerDatosNuevaPropuestaCasoDeUso obtenerDatosNueva,
    ObtenerPropuestasCasoDeUso          obtenerPropuestas,
    ObtenerPropuestaPorIdCasoDeUso      obtenerPropuestaPorId,
    GuardarPropuestaCasoDeUso           guardarPropuesta,
    ObtenerKpisPropuestasCasoDeUso      obtenerKpis,
    ObtenerDetallePropuestaCasoDeUso    obtenerDetalle,
    CrearNuevaVersionPropuestaCasoDeUso crearNuevaVersion) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>Datos heredados del requerimiento + propuesta existente (aviso de nueva versión).</summary>
    [HttpGet("nueva")]
    public async Task<IActionResult> ObtenerDatosNueva([FromQuery] long idRequerimiento, CancellationToken ct = default)
        => Responder(await obtenerDatosNueva.EjecutarAsync(idRequerimiento, ct), noEncontradoComo404: true);

    /// <summary>
    /// Bandeja de propuestas (HU-08). Filtros por query string: idRequerimiento, estado (BD),
    /// grupoEstado (todas | borrador | por_vb | en_seguimiento | aceptada | rechazada | cerrada),
    /// busqueda, anio, idComercial, soloUltimaVersion (true por defecto), pagina, porPagina.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> ObtenerPropuestas([FromQuery] FiltrosPropuestasDto filtros, CancellationToken ct = default)
        => Responder(await obtenerPropuestas.EjecutarAsync(filtros, ct));

    /// <summary>Tarjetas resumen de la bandeja (HU-08). Filtros opcionales: anio, idComercial.</summary>
    [HttpGet("kpis")]
    public async Task<IActionResult> ObtenerKpis([FromQuery] int? anio, [FromQuery] long? idComercial, CancellationToken ct = default)
        => Responder(await obtenerKpis.EjecutarAsync(anio, idComercial, ct));

    /// <summary>Propuesta completa: cabecera, ítems, textos, formas de pago y equipos.</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> ObtenerPropuestaPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerPropuestaPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>
    /// HU-09 — Modal "Detalle de Propuesta": la propuesta completa más workflow de aprobación,
    /// SLA de la etapa, documentos vinculados (RQ, expediente, OC, adjuntos), versiones,
    /// actividad y la acción principal (editar | nueva_version | ninguna).
    /// </summary>
    [HttpGet("{id:long}/detalle")]
    public async Task<IActionResult> ObtenerDetalle(long id, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>
    /// Guarda la propuesta completa (borrador). IdPropuesta = 0 crea;
    /// con IdPropuestaBase crea una nueva versión. Devuelve los totales recalculados.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> GuardarPropuesta([FromBody] GuardarPropuestaDto dto, CancellationToken ct = default)
        => Responder(await guardarPropuesta.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>
    /// HU-10 — Crea la siguiente versión (borrador) de la propuesta {id}, que debe ser la última
    /// y ya no estar en borrador. Requiere motivo y descripción de cambios; copia los bloques
    /// marcados. Si {id} aún no se había enviado al cliente (pendiente de VB o aprobada) queda anulada.
    /// Devuelve el id de la nueva versión para abrir el editor.
    /// </summary>
    [HttpPost("{id:long}/nueva-version")]
    public async Task<IActionResult> CrearNuevaVersion(long id, [FromBody] CrearNuevaVersionPropuestaDto dto, CancellationToken ct = default)
        => Responder(await crearNuevaVersion.EjecutarAsync(id, dto, IdUsuarioActual, ct));
}
