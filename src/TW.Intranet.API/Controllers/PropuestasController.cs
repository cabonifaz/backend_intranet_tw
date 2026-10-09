using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-07 / HU-08 / HU-09 / HU-10 / HU-11 / HU-12 — Propuestas comerciales.</summary>
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
    CrearNuevaVersionPropuestaCasoDeUso crearNuevaVersion,
    PrevisualizarDescuentoPropuestaCasoDeUso previsualizarDescuento,
    AplicarDescuentoPropuestaCasoDeUso       aplicarDescuento,
    QuitarDescuentoPropuestaCasoDeUso        quitarDescuento,
    PrepararVistoBuenoPropuestaCasoDeUso     prepararVistoBueno,
    EnviarVistoBuenoPropuestaCasoDeUso       enviarVistoBueno,
    PrepararAnulacionPropuestaCasoDeUso      prepararAnulacion,
    AnularPropuestaCasoDeUso                 anularPropuesta,
    GenerarPdfPropuestaCasoDeUso             generarPdf) : ControllerBase
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
    [RequierePermiso("propuesta_guardar")]
    [HttpGet("nueva")]
    public async Task<IActionResult> ObtenerDatosNueva([FromQuery] long idRequerimiento, CancellationToken ct = default)
        => Responder(await obtenerDatosNueva.EjecutarAsync(idRequerimiento, ct), noEncontradoComo404: true);

    /// <summary>
    /// Bandeja de propuestas (HU-08). Filtros por query string: idRequerimiento, estado (BD),
    /// grupoEstado (todas | borrador | por_vb | en_seguimiento | aceptada | rechazada | cerrada),
    /// busqueda, anio, idComercial, soloUltimaVersion (true por defecto), pagina, porPagina.
    /// </summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet]
    public async Task<IActionResult> ObtenerPropuestas([FromQuery] FiltrosPropuestasDto filtros, CancellationToken ct = default)
        => Responder(await obtenerPropuestas.EjecutarAsync(filtros, ct));

    /// <summary>Tarjetas resumen de la bandeja (HU-08). Filtros opcionales: anio, idComercial.</summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet("kpis")]
    public async Task<IActionResult> ObtenerKpis([FromQuery] int? anio, [FromQuery] long? idComercial, CancellationToken ct = default)
        => Responder(await obtenerKpis.EjecutarAsync(anio, idComercial, ct));

    /// <summary>Propuesta completa: cabecera, ítems, textos, formas de pago y equipos.</summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet("{id:long}")]
    public async Task<IActionResult> ObtenerPropuestaPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerPropuestaPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>
    /// HU-09 — Modal "Detalle de Propuesta": la propuesta completa más workflow de aprobación,
    /// SLA de la etapa, documentos vinculados (RQ, expediente, OC, adjuntos), versiones,
    /// actividad y la acción principal (editar | nueva_version | ninguna).
    /// </summary>
    [RequierePermiso("propuesta_ver")]
    [HttpGet("{id:long}/detalle")]
    public async Task<IActionResult> ObtenerDetalle(long id, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>
    /// Guarda la propuesta completa (borrador). IdPropuesta = 0 crea;
    /// con IdPropuestaBase crea una nueva versión. Devuelve los totales recalculados.
    /// </summary>
    [RequierePermiso("propuesta_guardar")]
    [HttpPost]
    public async Task<IActionResult> GuardarPropuesta([FromBody] GuardarPropuestaDto dto, CancellationToken ct = default)
        => Responder(await guardarPropuesta.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>
    /// HU-10 — Crea la siguiente versión (borrador) de la propuesta {id}, que debe ser la última
    /// y ya no estar en borrador. Requiere motivo y descripción de cambios; copia los bloques
    /// marcados. Si {id} aún no se había enviado al cliente (pendiente de VB o aprobada) queda anulada.
    /// Devuelve el id de la nueva versión para abrir el editor.
    /// </summary>
    [RequierePermiso("propuesta_nueva_version")]
    [HttpPost("{id:long}/nueva-version")]
    public async Task<IActionResult> CrearNuevaVersion(long id, [FromBody] CrearNuevaVersionPropuestaDto dto, CancellationToken ct = default)
        => Responder(await crearNuevaVersion.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    // ── HU-11: descuento global ─────────────────────────────────────────────

    /// <summary>
    /// Calcula, sin guardar, los nuevos montos (descuento, subtotal, IGV y total) para el modal.
    /// Misma fórmula que al guardar. El motivo es opcional aquí.
    /// </summary>
    [RequierePermiso("propuesta_aplicar_descuento")]
    [HttpPost("{id:long}/descuento/previsualizar")]
    public async Task<IActionResult> PrevisualizarDescuento(long id, [FromBody] AplicarDescuentoPropuestaDto dto, CancellationToken ct = default)
        => Responder(await previsualizarDescuento.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    /// <summary>
    /// Aplica el descuento global (porcentaje o monto fijo) con motivo obligatorio.
    /// Solo propuestas en borrador. Requiere propuesta_aplicar_descuento (Jefe Comercial o administrador).
    /// </summary>
    [RequierePermiso("propuesta_aplicar_descuento")]
    [HttpPut("{id:long}/descuento")]
    public async Task<IActionResult> AplicarDescuento(long id, [FromBody] AplicarDescuentoPropuestaDto dto, CancellationToken ct = default)
        => Responder(await aplicarDescuento.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    /// <summary>Quita el descuento global. Solo propuestas en borrador.</summary>
    [RequierePermiso("propuesta_aplicar_descuento")]
    [HttpDelete("{id:long}/descuento")]
    public async Task<IActionResult> QuitarDescuento(long id, CancellationToken ct = default)
        => Responder(await quitarDescuento.EjecutarAsync(id, IdUsuarioActual, ct));

    // ── HU-12: envío a visto bueno ──────────────────────────────────────────

    /// <summary>
    /// Datos del modal "Enviar a Visto Bueno": validaciones del sistema, aprobador (jefe directo
    /// o su suplente vigente), SLA con fecha límite y alerta de aprobación especial. No cambia nada.
    /// </summary>
    [RequierePermiso("propuesta_enviar_vb")]
    [HttpGet("{id:long}/visto-bueno/preparar")]
    public async Task<IActionResult> PrepararVistoBueno(long id, CancellationToken ct = default)
        => Responder(await prepararVistoBueno.EjecutarAsync(id, IdUsuarioActual, ct));

    /// <summary>
    /// Envía la propuesta (borrador, última versión) a visto bueno: pasa a pendiente_vb, crea el
    /// registro de VB con su SLA y notifica al aprobador. Comentario obligatorio si requiere aprobación especial.
    /// </summary>
    [RequierePermiso("propuesta_enviar_vb")]
    [HttpPost("{id:long}/visto-bueno")]
    public async Task<IActionResult> EnviarVistoBueno(long id, [FromBody] EnviarVistoBuenoPropuestaDto? dto, CancellationToken ct = default)
        => Responder(await enviarVistoBueno.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    // ── HU-12: anulación ────────────────────────────────────────────────────

    /// <summary>Datos del modal "Anular Propuesta": impacto, si se puede anular y motivos.</summary>
    [RequierePermiso("propuesta_anular")]
    [HttpGet("{id:long}/anulacion/preparar")]
    public async Task<IActionResult> PrepararAnulacion(long id, CancellationToken ct = default)
        => Responder(await prepararAnulacion.EjecutarAsync(id, IdUsuarioActual, ct));

    /// <summary>
    /// Anula la propuesta (última versión, sin OC vinculada). Exige motivo, justificación de
    /// al menos 20 caracteres y confirmacionCritica = true. Cancela el VB pendiente.
    /// </summary>
    [RequierePermiso("propuesta_anular")]
    [HttpPost("{id:long}/anular")]
    public async Task<IActionResult> Anular(long id, [FromBody] AnularPropuestaDto dto, CancellationToken ct = default)
        => Responder(await anularPropuesta.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    // ── Vista Previa / Descarga PDF ─────────────────────────────────────────

    /// <summary>
    /// Genera el PDF comercial de la propuesta (vista previa + descarga).
    /// Reutiliza el detalle completo y lo renderiza con QuestPDF.
    /// </summary>
    [HttpGet("{id:long}/pdf")]
    public async Task<IActionResult> ObtenerPdf(long id, CancellationToken ct = default)
    {
        var r = await generarPdf.EjecutarAsync(id, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return r.IdTipoMensaje == 1 ? BadRequest(new RespuestaDto<object>(1, r.Mensaje))
                                        : StatusCode(500, new RespuestaDto<object>(3, r.Mensaje));
        return File(r.Datos, "application/pdf", $"propuesta-{id}.pdf");
    }
}
