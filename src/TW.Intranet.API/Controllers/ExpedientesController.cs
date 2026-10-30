using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Expediente Digital (Sprint 4): bandeja (HU-29), ficha con 11 tabs de carga perezosa (HU-30), repositorio de
/// documentos (HU-31), historial de auditoría (HU-32) y reasignación de responsables (HU-33).
/// El expediente es de consulta: nace con el RQ, sus etapas avanzan solas según el flujo y los documentos y bloqueos se
/// gestionan en los módulos origen ("Ir al módulo origen").
/// </summary>
[ApiController]
[Authorize]
[Route("api/expedientes")]
public class ExpedientesController(
    ObtenerBandejaExpedientesCasoDeUso          obtenerBandeja,
    ExportarBandejaExpedientesCasoDeUso         exportarBandeja,
    ObtenerDetalleExpedienteCasoDeUso           obtenerDetalle,
    ObtenerTabRqExpedienteCasoDeUso             tabRq,
    ObtenerTabPropuestasExpedienteCasoDeUso     tabPropuestas,
    CompararVersionesExpedienteCasoDeUso        compararVersiones,
    ObtenerTabVistoBuenoExpedienteCasoDeUso     tabVistoBueno,
    ObtenerTabSeguimientoExpedienteCasoDeUso    tabSeguimiento,
    ObtenerTabOrdenesCompraExpedienteCasoDeUso  tabOrdenesCompra,
    ObtenerTabOrdenServicioExpedienteCasoDeUso  tabOrdenServicio,
    ObtenerTabProgramacionExpedienteCasoDeUso   tabProgramacion,
    ObtenerTabSsomaExpedienteCasoDeUso          tabSsoma,
    ObtenerTabEjecucionExpedienteCasoDeUso      tabEjecucion,
    ObtenerTabCierreExpedienteCasoDeUso         tabCierre,
    ExportarExpedienteCasoDeUso                 exportarExpediente,
    ObtenerDocumentosExpedienteCasoDeUso        obtenerDocumentos,
    ExportarDocumentosExpedienteCasoDeUso       exportarDocumentos,
    ObtenerArchivoExpedienteCasoDeUso           obtenerArchivo,
    ObtenerHistorialExpedienteCasoDeUso         obtenerHistorial,
    ExportarHistorialExpedienteCasoDeUso        exportarHistorial,
    PrepararReasignacionExpedienteCasoDeUso     prepararReasignacion,
    ObtenerCarteraComercialExpedienteCasoDeUso  obtenerCartera,
    BuscarResponsablesExpedienteCasoDeUso       buscarResponsables,
    ReasignarResponsableExpedienteCasoDeUso     reasignar) : ControllerBase
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

    private IActionResult Archivo(RespuestaDto<ArchivoGeneradoDto> r)
    {
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje));
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    // ── HU-29 Bandeja ────────────────────────────────────────────────────────

    /// <summary>
    /// HU-29 — Bandeja: 5 tarjetas (filtro rápido con ?estado=), tabla de 8 columnas paginada y opciones de los filtros.
    /// ?estado=abiertos|listo_para_avanzar|bloqueado|con_excepcion|sla_vencido|activo|cerrado|todos &amp;etapa= &amp;idCliente=
    /// &amp;area= &amp;tipoPropuesta= &amp;desde=yyyy-MM-dd &amp;hasta= &amp;sla=en_plazo|en_riesgo|vencido &amp;busqueda= &amp;pagina=1 &amp;porPagina=10
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaExpedientesDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>HU-29 — Exportar XLSX con los mismos filtros de la bandeja (todas las filas, sin paginar).</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("xlsx")]
    public async Task<IActionResult> ExportarBandeja([FromQuery] FiltrosBandejaExpedientesDto filtros, CancellationToken ct = default)
        => Archivo(await exportarBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    // ── HU-30 Ficha ──────────────────────────────────────────────────────────

    /// <summary>
    /// HU-30 — Sección primaria (cabecera, KPIs, contadores de tabs y permisos) y tab 📊 Resumen: stepper de las 10 etapas,
    /// responsables actuales, árbol de entidades, alertas y bloqueos activos y actividad reciente.
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}")]
    public async Task<IActionResult> Detalle(long idExpediente, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 📄 RQ: datos, contacto y sede del cliente, adjuntos, timeline del RQ y propuestas generadas.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/rq")]
    public async Task<IActionResult> TabRq(long idExpediente, CancellationToken ct = default)
        => Responder(await tabRq.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 📝 Propuestas: pills por versión y detalle de la elegida. ?idPropuesta= (por defecto la activa).</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/propuestas")]
    public async Task<IActionResult> TabPropuestas(long idExpediente, [FromQuery] long? idPropuesta, CancellationToken ct = default)
        => Responder(await tabPropuestas.EjecutarAsync(idExpediente, idPropuesta, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab Propuestas, "Comparar versiones": ?base={idPropuesta}&amp;destino={idPropuesta} (de la misma propuesta).</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/propuestas/comparar")]
    public async Task<IActionResult> CompararVersiones(long idExpediente, [FromQuery(Name = "base")] long idBase,
                                                       [FromQuery(Name = "destino")] long idDestino, CancellationToken ct = default)
        => Responder(await compararVersiones.EjecutarAsync(idExpediente, idBase, idDestino, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab ✓ Visto Bueno: estado, historial de decisiones, reasignaciones del aprobador y métricas. ?numero=PROP-000001</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/visto-bueno")]
    public async Task<IActionResult> TabVistoBueno(long idExpediente, [FromQuery] string? numero, CancellationToken ct = default)
        => Responder(await tabVistoBueno.EjecutarAsync(idExpediente, numero, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 📞 Seguimiento: estado, timeline de interacciones, resultado y evidencias. ?numero=PROP-000001</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/seguimiento")]
    public async Task<IActionResult> TabSeguimiento(long idExpediente, [FromQuery] string? numero, CancellationToken ct = default)
        => Responder(await tabSeguimiento.EjecutarAsync(idExpediente, numero, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 🧾 OC: pills por OC y detalle (datos, validación IA, campos, timeline). ?idOc=</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/ordenes-compra")]
    public async Task<IActionResult> TabOrdenesCompra(long idExpediente, [FromQuery] long? idOc, CancellationToken ct = default)
        => Responder(await tabOrdenesCompra.EjecutarAsync(idExpediente, idOc, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab ⚙️ OS: datos de la OS, personal, equipos, viáticos y OM. ?idOs=</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/orden-servicio")]
    public async Task<IActionResult> TabOrdenServicio(long idExpediente, [FromQuery] long? idOs, CancellationToken ct = default)
        => Responder(await tabOrdenServicio.EjecutarAsync(idExpediente, idOs, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 📅 Programación: calendario, recursos reservados, backlog y checklist de presalida.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/programacion")]
    public async Task<IActionResult> TabProgramacion(long idExpediente, CancellationToken ct = default)
        => Responder(await tabProgramacion.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 🛡️ SSOMA: resumen, checklist por técnico, documentos y requisitos del cliente.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/ssoma")]
    public async Task<IActionResult> TabSsoma(long idExpediente, CancellationToken ct = default)
        => Responder(await tabSsoma.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab 🚀 Ejecución: eventos de campo (GPS), evidencias, incidencias y demoras.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/ejecucion")]
    public async Task<IActionResult> TabEjecucion(long idExpediente, CancellationToken ct = default)
        => Responder(await tabEjecucion.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Tab ✓ Cierre: conformidad del cliente, informes técnicos, certificados y fecha de cierre.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/cierre")]
    public async Task<IActionResult> TabCierre(long idExpediente, CancellationToken ct = default)
        => Responder(await tabCierre.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — ⬇ Exportar Expediente Completo (.zip): expediente.xlsx y los documentos por carpeta.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/exportar")]
    public async Task<IActionResult> ExportarExpediente(long idExpediente, CancellationToken ct = default)
    {
        var r = await exportarExpediente.EjecutarAsync(idExpediente, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje));
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    // ── HU-31 Documentos ─────────────────────────────────────────────────────

    /// <summary>
    /// HU-31 — Modal de documentos (solo lectura): pestañas con cantidad, documentos y opciones de filtros.
    /// ?categoria=todos|comerciales|operativos|ssoma|tecnicos &amp;busqueda= &amp;desde= &amp;hasta= &amp;estado= &amp;formato= &amp;orden=desc|asc
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/documentos")]
    public async Task<IActionResult> Documentos(long idExpediente, [FromQuery] FiltrosDocumentosExpedienteDto filtros, CancellationToken ct = default)
        => Responder(await obtenerDocumentos.EjecutarAsync(idExpediente, filtros, IdUsuarioActual, ct));

    /// <summary>HU-31 — ⬇ Exportar lista XLSX (metadata, no los archivos) con la pestaña y filtros activos.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/documentos/xlsx")]
    public async Task<IActionResult> ExportarDocumentos(long idExpediente, [FromQuery] FiltrosDocumentosExpedienteDto filtros, CancellationToken ct = default)
        => Archivo(await exportarDocumentos.EjecutarAsync(idExpediente, filtros, IdUsuarioActual, ct));

    /// <summary>
    /// HU-31 — 👁 Preview (inline) o ⬇ Descargar (?descargar=true) un documento por su clave (ej. doc-12, prop-5, mail-3, ssoma-3).
    /// Requiere el token: el front lo pide como blob (no con window.open).
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/documentos/{clave}")]
    public async Task<IActionResult> Descargar(long idExpediente, string clave, [FromQuery] bool descargar = false, CancellationToken ct = default)
    {
        var r = await obtenerArchivo.EjecutarAsync(idExpediente, clave, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return r.IdTipoMensaje == 1 ? NotFound(new RespuestaDto<object>(1, r.Mensaje)) : StatusCode(500, new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje));

        // Vista previa en línea solo para PDF e imágenes; cualquier otro tipo (HTML, SVG…) se descarga siempre
        var enLinea = !descargar && r.Datos.TipoContenido is "application/pdf" or "image/png" or "image/jpeg";
        var disposicion = new ContentDispositionHeaderValue(enLinea ? "inline" : "attachment");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        Response.Headers[HeaderNames.XContentTypeOptions] = "nosniff";
        return File(r.Datos.Contenido, enLinea ? r.Datos.TipoContenido : "application/octet-stream", enableRangeProcessing: enLinea);
    }

    // ── HU-32 Historial de auditoría ─────────────────────────────────────────

    /// <summary>
    /// HU-32 — Historial de auditoría (solo lectura): los 4 tabs (Timeline, Reasignaciones, Bloqueos, Alertas SLA) con su
    /// cantidad y las opciones de filtros. ?busqueda= &amp;idUsuario= &amp;etapa= &amp;tipoEvento= &amp;desde= &amp;hasta=
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/historial")]
    public async Task<IActionResult> Historial(long idExpediente, [FromQuery] FiltrosHistorialExpedienteDto filtros, CancellationToken ct = default)
        => Responder(await obtenerHistorial.EjecutarAsync(idExpediente, filtros, IdUsuarioActual, ct));

    /// <summary>
    /// HU-32 — ⬇ Exportar el tab activo con los filtros aplicados. ?tab=timeline|reasignaciones|bloqueos|alertas_sla
    /// &amp;formato=xlsx|pdf (+ los filtros del historial). Queda registrado en la auditoría.
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/historial/exportar")]
    public async Task<IActionResult> ExportarHistorial(long idExpediente, [FromQuery] string? tab, [FromQuery] string? formato,
                                                       [FromQuery] FiltrosHistorialExpedienteDto filtros, CancellationToken ct = default)
        => Archivo(await exportarHistorial.EjecutarAsync(idExpediente, tab, formato, filtros, IdUsuarioActual, ct));

    // ── HU-33 Reasignación ───────────────────────────────────────────────────

    /// <summary>
    /// HU-33 — Datos del modal "Reasignar Responsable" (Opciones A y B): responsable actual, entidades activas reasignables
    /// con su árbol (clavePadre), motivos y gestión del SLA. Solo en etapa comercial.
    /// </summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpGet("{idExpediente:long}/reasignacion")]
    public async Task<IActionResult> PrepararReasignacion(long idExpediente, CancellationToken ct = default)
        => Responder(await prepararReasignacion.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-33 — Opción C: impacto global de la cartera del comercial. ?idResponsable= (por defecto el actual del expediente).</summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpGet("{idExpediente:long}/reasignacion/cartera")]
    public async Task<IActionResult> CarteraComercial(long idExpediente, [FromQuery] long? idResponsable, CancellationToken ct = default)
        => Responder(await obtenerCartera.EjecutarAsync(idExpediente, idResponsable, IdUsuarioActual, ct));

    /// <summary>HU-33 — Buscar el nuevo responsable (rol Comercial). ?busqueda= &amp;excluir={idUsuario actual}</summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpGet("reasignacion/candidatos")]
    public async Task<IActionResult> Candidatos([FromQuery] string? busqueda, [FromQuery] long? excluir, CancellationToken ct = default)
        => Responder(await buscarResponsables.EjecutarAsync(busqueda, excluir, IdUsuarioActual, ct));

    /// <summary>
    /// HU-33 — Confirmar Reasignación. Body: { modo: entidad|cascada|global, entidadTipo, idEntidad, excluidos: ["oc-12"],
    /// idResponsableActual (global), idNuevoResponsable, idMotivo, comentario (≥ 20), gestionSla: mantener|reiniciar }.
    /// </summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpPost("{idExpediente:long}/reasignar")]
    public async Task<IActionResult> Reasignar(long idExpediente, [FromBody] ReasignarResponsableExpedienteDto datos, CancellationToken ct = default)
        => Responder(await reasignar.EjecutarAsync(idExpediente, datos, IdUsuarioActual, ct));
}
