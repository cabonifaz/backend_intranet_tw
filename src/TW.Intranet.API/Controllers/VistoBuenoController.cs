using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-13 Bandeja de Visto Bueno · HU-14 Revisión y comparación · HU-15 Emisión de decisiones.</summary>
[ApiController]
[Authorize]
public class VistoBuenoController(
    ObtenerBandejaVistoBuenoCasoDeUso       obtenerBandeja,
    ResolverVistoBuenoCasoDeUso             resolver,
    ObtenerValidacionesVistoBuenoCasoDeUso  obtenerValidaciones,
    CompararVersionesPropuestaCasoDeUso     comparar,
    ObtenerCostoSuministroCasoDeUso         obtenerCosto,
    GuardarCostoSuministroCasoDeUso         guardarCosto,
    PrepararDecisionVistoBuenoCasoDeUso     prepararDecision,
    ObtenerCorreccionPropuestaCasoDeUso     obtenerCorreccion) : ControllerBase
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
    /// HU-13 — Bandeja de visto bueno del equipo del usuario (o de su titular si es suplente).
    /// Devuelve KPIs, filas, opciones de filtro (comerciales y monedas) y políticas.
    /// </summary>
    [RequierePermiso("propuesta_vb_bandeja")]
    [HttpGet("api/crm/visto-bueno")]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaVistoBuenoDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>
    /// HU-13 / HU-15 — Aprobar, solicitar corrección o rechazar.
    /// aprobar: { accion, validacionesConfirmadas: [códigos], comentario? }
    /// rechazar: { accion, idMotivoRechazo, comentario (justificación) }
    /// corregir: { accion, areas: [códigos], comentario (observaciones), fechaLimite }
    /// </summary>
    [RequierePermiso("propuesta_vb_resolver")]
    [HttpPost("api/crm/propuestas/{id:long}/visto-bueno/resolver")]
    public async Task<IActionResult> Resolver(long id, [FromBody] ResolverVistoBuenoDto dto, CancellationToken ct = default)
        => Responder(await resolver.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    /// <summary>HU-14 — Validaciones previas: crédito, margen, descuento y stock, con el riesgo financiero.</summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet("api/crm/propuestas/{id:long}/validaciones")]
    public async Task<IActionResult> Validaciones(long id, CancellationToken ct = default)
        => Responder(await obtenerValidaciones.EjecutarAsync(id, IdUsuarioActual, ct));

    /// <summary>HU-14 — Comparar dos versiones de la misma propuesta: ?base={idPropuesta}&amp;destino={idPropuesta}.</summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet("api/crm/propuestas/comparar")]
    public async Task<IActionResult> Comparar([FromQuery(Name = "base")] long idBase, [FromQuery(Name = "destino")] long idDestino,
                                              CancellationToken ct = default)
        => Responder(await comparar.EjecutarAsync(idBase, idDestino, IdUsuarioActual, ct));

    /// <summary>Precio de costo del suministro (solo jefaturas).</summary>
    [RequierePermiso("suministro_costo_ver")]
    [HttpGet("api/maestros/suministros/{id:long}/costo")]
    public async Task<IActionResult> ObtenerCosto(long id, CancellationToken ct = default)
        => Responder(await obtenerCosto.EjecutarAsync(id, ct));

    /// <summary>Registrar o quitar (null) el precio de costo del suministro, en su moneda.</summary>
    [RequierePermiso("suministro_costo_guardar")]
    [HttpPut("api/maestros/suministros/{id:long}/costo")]
    public async Task<IActionResult> GuardarCosto(long id, [FromBody] GuardarCostoSuministroDto dto, CancellationToken ct = default)
        => Responder(await guardarCosto.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    /// <summary>
    /// HU-15 — Datos de los modales de decisión: si el usuario puede resolver, validaciones
    /// requeridas para aprobar, motivos de rechazo, áreas a corregir y fecha límite sugerida.
    /// </summary>
    [RequierePermiso("propuesta_vb_resolver")]
    [HttpGet("api/crm/propuestas/{id:long}/visto-bueno/decision")]
    public async Task<IActionResult> PrepararDecision(long id, CancellationToken ct = default)
        => Responder(await prepararDecision.EjecutarAsync(id, IdUsuarioActual, ct));

    /// <summary>HU-15 — Última solicitud de corrección (áreas, observaciones, fecha límite, estado). datos = null si no tiene.</summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet("api/crm/propuestas/{id:long}/correccion")]
    public async Task<IActionResult> Correccion(long id, CancellationToken ct = default)
        => Responder(await obtenerCorreccion.EjecutarAsync(id, ct));
}
