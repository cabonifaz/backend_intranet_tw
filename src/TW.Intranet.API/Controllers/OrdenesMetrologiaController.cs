using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Módulo 13 Órdenes de Metrología (OM), Sprint 6 (HU-61 a HU-65). Vista separada de Órdenes de Servicio a pedido del cliente:
/// mismas rutas, filtros y DTOs que /api/crm/ordenes-servicio, pero solo con órdenes de tipo OM.
/// La OM vive en orden_servicio (tipo = 'OM', migración 80): así la siguen leyendo Programación, Expediente y la app móvil, y el
/// correlativo OM-NNNNNN ya es independiente del de OS. Cada ruta fija el tipo OM o comprueba (SP_ObtenerTipoOrdenServicio) que la
/// orden, la propuesta o la solicitud sean de metrología; si no, responde 400. El historial es por orden: el de una OM no se mezcla con OS.
/// Permisos: por ahora los mismos de OS (os_bandeja, os_bandeja_operaciones, os_guardar, os_anular, os_aprobar_edicion), porque los SPs los validan.
/// </summary>
[ApiController]
[Route("api/crm/ordenes-metrologia")]
[Authorize]
public class OrdenesMetrologiaController(
    ValidarTipoOrdenCasoDeUso                    validarTipo,
    ObtenerBandejaOrdenesServicioCasoDeUso       obtenerBandeja,
    ExportarBandejaOrdenesServicioCasoDeUso      exportarBandeja,
    PrepararOrdenServicioCasoDeUso               preparar,
    GuardarOrdenServicioCasoDeUso                guardar,
    PrepararSolicitudEdicionOsCasoDeUso          prepararSolicitud,
    SolicitarEdicionOsCasoDeUso                  solicitarEdicion,
    ResolverSolicitudEdicionOsCasoDeUso          resolverSolicitud,
    PrepararAnulacionOsCasoDeUso                 prepararAnulacion,
    AnularOrdenServicioCasoDeUso                 anular,
    ObtenerDetalleOrdenServicioCasoDeUso         obtenerDetalle,
    ObtenerTabsOrdenServicioCasoDeUso            tabs,
    BuscarEquiposOrdenServicioCasoDeUso          buscarEquipos,
    BuscarConceptosOrdenServicioCasoDeUso        buscarConceptos,
    DescargarPlantillaImportacionOsCasoDeUso     plantilla,
    AnalizarImportacionOsCasoDeUso               analizarImportacion,
    ObtenerPropuestasDisponiblesOsCasoDeUso      propuestasDisponibles,
    ObtenerMotivosOrdenServicioCasoDeUso         motivos,
    GenerarPdfOrdenServicioCasoDeUso             generarPdf) : ControllerBase
{
    private const string Tipo = "OM";
    private const long TamanoMaximoPeticion = 6 * 1024 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) => r.IdTipoMensaje switch
    {
        2 => Ok(r),
        1 => BadRequest(r),
        _ => StatusCode(500, r),
    };

    /// <summary>null si la orden / propuesta / solicitud es una OM; si no, la respuesta de error (400 o 500).</summary>
    private async Task<IActionResult?> SiNoEsOm(long? idOm, long? idPropuesta, long? idSolicitud, CancellationToken ct)
    {
        var r = await validarTipo.EjecutarAsync(Tipo, idOm, idPropuesta, idSolicitud, ct);
        return r.IdTipoMensaje == 2 ? null : Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje));
    }

    // ══════════════════════ HU-62 Bandeja ══════════════════════

    /// <summary>
    /// Bandeja de OM: tarjetas por estado, filas, total y opciones de filtro.
    /// ?estado=todas|borrador|emitida|programada|en_ejecucion|finalizada|anulada &amp;idCliente=&amp;idResponsable=&amp;fechaDesde=&amp;fechaHasta=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// (el filtro tipo se ignora: siempre OM).
    /// </summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaOrdenesServicioDto filtros, CancellationToken ct = default)
    {
        filtros.Tipo = Tipo;
        return Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));
    }

    /// <summary>Exportar XLSX con los mismos filtros de la bandeja (solo OM).</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("exportar")]
    public async Task<IActionResult> Exportar([FromQuery] FiltrosBandejaOrdenesServicioDto filtros, CancellationToken ct = default)
    {
        filtros.Tipo = Tipo;
        var r = await exportarBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    // ══════════════════════ HU-61 Crear / editar / solicitar edición / anular ══════════════════════

    /// <summary>Modal "Elegir Propuesta Aceptada" (solo las que generan OM): ?busqueda=&amp;pagina=1&amp;porPagina=10</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("propuestas-disponibles")]
    public async Task<IActionResult> PropuestasDisponibles([FromQuery] FiltrosPropuestasDisponiblesOsDto filtros, CancellationToken ct = default)
    {
        filtros.Tipo = Tipo;
        return Responder(await propuestasDisponibles.EjecutarAsync(filtros, IdUsuarioActual, ct));
    }

    /// <summary>Ficha "Nueva OM" desde una propuesta aceptada de metrología.</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("preparar")]
    [HttpGet("preparar-nueva")]
    public async Task<IActionResult> Preparar([FromQuery] long idPropuesta, CancellationToken ct = default)
    {
        if (await SiNoEsOm(null, idPropuesta, null, ct) is { } error) return error;
        return Responder(await preparar.EjecutarAsync(idPropuesta, null, IdUsuarioActual, ct));
    }

    /// <summary>Ficha de edición: borrador, o emitida con la edición aprobada por el Jefe Comercial.</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("{idOm:long}/edicion")]
    [HttpGet("{idOm:long}/preparar-edicion")]
    public async Task<IActionResult> PrepararEdicion(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await preparar.EjecutarAsync(null, idOm, IdUsuarioActual, ct));
    }

    /// <summary>Crea la OM (borrador, o emitida si emitir = true). Correlativo OM-NNNNNN, independiente del de OS.</summary>
    [RequierePermiso("os_guardar")]
    [HttpPost]
    public async Task<IActionResult> Crear([FromBody] GuardarOrdenServicioDto? datos, CancellationToken ct = default)
    {
        if (datos?.IdPropuesta is > 0 && await SiNoEsOm(null, datos.IdPropuesta, null, ct) is { } error) return error;
        return Responder(await guardar.EjecutarAsync(0, datos, IdUsuarioActual, ct));
    }

    /// <summary>Guarda el borrador / lo emite, o guarda la edición autorizada (re-emite y notifica a Operaciones).</summary>
    [RequierePermiso("os_guardar")]
    [HttpPut("{idOm:long}")]
    public async Task<IActionResult> Actualizar(long idOm, [FromBody] GuardarOrdenServicioDto? datos, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await guardar.EjecutarAsync(idOm, datos, IdUsuarioActual, ct));
    }

    /// <summary>Modal "Solicitar edición": a quién se envía (Jefe Comercial) y motivos.</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("{idOm:long}/solicitud-edicion/preparar")]
    public async Task<IActionResult> PrepararSolicitudEdicion(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await prepararSolicitud.EjecutarAsync(idOm, IdUsuarioActual, ct));
    }

    /// <summary>Envía la solicitud de edición: { idMotivo, comentario (20 a 500) }. Notifica al Jefe Comercial.</summary>
    [RequierePermiso("os_guardar")]
    [HttpPost("{idOm:long}/solicitud-edicion")]
    [HttpPost("{idOm:long}/solicitar-edicion")]
    public async Task<IActionResult> SolicitarEdicion(long idOm, [FromBody] SolicitarEdicionOsDto? datos, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await solicitarEdicion.EjecutarAsync(idOm, datos, IdUsuarioActual, ct));
    }

    /// <summary>Jefe Comercial: { aprobar, comentario (obligatorio al rechazar, mín. 10) }.</summary>
    [RequierePermiso("os_aprobar_edicion")]
    [HttpPost("solicitudes/{idSolicitud:long}/resolver")]
    public async Task<IActionResult> ResolverSolicitud(long idSolicitud, [FromBody] ResolverSolicitudEdicionOsDto? datos, CancellationToken ct = default)
    {
        if (await SiNoEsOm(null, null, idSolicitud, ct) is { } error) return error;
        return Responder(await resolverSolicitud.EjecutarAsync(idSolicitud, datos, IdUsuarioActual, ct));
    }

    /// <summary>Jefe Comercial aprueba la edición: { comentario } opcional.</summary>
    [RequierePermiso("os_aprobar_edicion")]
    [HttpPost("{idOm:long}/solicitud-edicion/{idSolicitud:long}/aprobar")]
    [HttpPost("{idOm:long}/solicitudes/{idSolicitud:long}/aprobar")]
    public async Task<IActionResult> AprobarSolicitud(long idOm, long idSolicitud, [FromBody] ComentarioSolicitudOsDto? datos, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, idSolicitud, ct) is { } error) return error;
        return Responder(await resolverSolicitud.EjecutarAsync(idSolicitud, new ResolverSolicitudEdicionOsDto { Aprobar = true, Comentario = datos?.Comentario },
                                                              IdUsuarioActual, ct));
    }

    /// <summary>Jefe Comercial rechaza la edición: { comentario } obligatorio (mín. 10 caracteres).</summary>
    [RequierePermiso("os_aprobar_edicion")]
    [HttpPost("{idOm:long}/solicitud-edicion/{idSolicitud:long}/rechazar")]
    [HttpPost("{idOm:long}/solicitudes/{idSolicitud:long}/rechazar")]
    public async Task<IActionResult> RechazarSolicitud(long idOm, long idSolicitud, [FromBody] ComentarioSolicitudOsDto? datos, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, idSolicitud, ct) is { } error) return error;
        return Responder(await resolverSolicitud.EjecutarAsync(idSolicitud, new ResolverSolicitudEdicionOsDto { Aprobar = false, Comentario = datos?.Comentario },
                                                              IdUsuarioActual, ct));
    }

    /// <summary>Catálogo de motivos de edición (el mismo de OS).</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("motivos-edicion")]
    public async Task<IActionResult> MotivosEdicion(CancellationToken ct = default)
        => Responder(await motivos.EjecutarAsync("edicion", IdUsuarioActual, ct));

    /// <summary>Catálogo de motivos de anulación (el mismo de OS).</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("motivos-anulacion")]
    public async Task<IActionResult> MotivosAnulacion(CancellationToken ct = default)
        => Responder(await motivos.EjecutarAsync("anulacion", IdUsuarioActual, ct));

    /// <summary>Modal Anular: impacto en la programación (técnico, fecha, viáticos, personal) y motivos.</summary>
    [RequierePermiso("os_anular")]
    [HttpGet("{idOm:long}/anulacion/preparar")]
    [HttpGet("{idOm:long}/impacto-anulacion")]
    public async Task<IActionResult> PrepararAnulacion(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await prepararAnulacion.EjecutarAsync(idOm, IdUsuarioActual, ct));
    }

    /// <summary>Anula: { idMotivo, comentario (20 a 500) }. Libera personal y viáticos asignados.</summary>
    [RequierePermiso("os_anular")]
    [HttpPost("{idOm:long}/anular")]
    public async Task<IActionResult> Anular(long idOm, [FromBody] AnularOrdenServicioDto? datos, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await anular.EjecutarAsync(idOm, datos, IdUsuarioActual, ct));
    }

    // ══════════════════════ HU-63 Detalle (tabs con carga perezosa) ══════════════════════

    /// <summary>Cabecera, tab Resumen, acciones permitidas y Avance por equipos.</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}")]
    public async Task<IActionResult> Detalle(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await obtenerDetalle.EjecutarAsync(idOm, IdUsuarioActual, ct));
    }

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/propuesta")]
    public async Task<IActionResult> TabPropuesta(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await tabs.PropuestaAsync(idOm, IdUsuarioActual, ct));
    }

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/equipos")]
    public async Task<IActionResult> TabEquipos(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await tabs.EquiposAsync(idOm, IdUsuarioActual, ct));
    }

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/conceptos")]
    public async Task<IActionResult> TabConceptos(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await tabs.ConceptosAsync(idOm, IdUsuarioActual, ct));
    }

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/observaciones")]
    public async Task<IActionResult> TabObservaciones(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await tabs.ObservacionesAsync(idOm, IdUsuarioActual, ct));
    }

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/programacion")]
    public async Task<IActionResult> TabProgramacion(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await tabs.ProgramacionAsync(idOm, IdUsuarioActual, ct));
    }

    /// <summary>Datos del certificado de la OM.</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/certificado")]
    public async Task<IActionResult> TabCertificado(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        return Responder(await tabs.CertificadoAsync(idOm, IdUsuarioActual, ct));
    }

    /// <summary>PDF oficial de la OM (cualquier estado). Responde application/pdf.</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOm:long}/pdf")]
    public async Task<IActionResult> Pdf(long idOm, CancellationToken ct = default)
    {
        if (await SiNoEsOm(idOm, null, null, ct) is { } error) return error;
        var r = await generarPdf.EjecutarAsync(idOm, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return r.IdTipoMensaje == 1 ? BadRequest(new RespuestaDto<object>(1, r.Mensaje))
                                        : StatusCode(500, new RespuestaDto<object>(3, r.Mensaje));
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    // ══════════════════════ HU-64 Buscadores ══════════════════════

    /// <summary>Equipos del cliente: ?idCliente=&amp;idOs=&amp;busqueda=&amp;clasificacion=equipo|instrumento|pesa&amp;ubicacion=&amp;idPropuesta=&amp;pagina=1&amp;porPagina=20</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("catalogo-equipos")]
    [HttpGet("equipos-cliente")]
    public async Task<IActionResult> BuscarEquipos([FromQuery] FiltrosBuscarEquiposOsDto filtros, CancellationToken ct = default)
    {
        if (filtros.IdOs is > 0 && await SiNoEsOm(filtros.IdOs, null, null, ct) is { } error) return error;
        return Responder(await buscarEquipos.EjecutarAsync(filtros, IdUsuarioActual, ct));
    }

    /// <summary>Conceptos (suministros de clase Servicio): ?busqueda=&amp;tipo=&amp;idPropuesta=&amp;pagina=1&amp;porPagina=20</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("catalogo-conceptos")]
    [HttpGet("conceptos")]
    public async Task<IActionResult> BuscarConceptos([FromQuery] FiltrosBuscarConceptosOsDto filtros, CancellationToken ct = default)
    {
        if (filtros.IdPropuesta is > 0 && await SiNoEsOm(null, filtros.IdPropuesta, null, ct) is { } error) return error;
        return Responder(await buscarConceptos.EjecutarAsync(filtros, IdUsuarioActual, ct));
    }

    // ══════════════════════ HU-65 Importación por Excel ══════════════════════

    /// <summary>Plantilla oficial (.xlsx): hojas Conceptos y Equipos (la misma de OS).</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("importar/plantilla")]
    [HttpGet("importacion/plantilla")]
    public IActionResult Plantilla()
    {
        var a = plantilla.Ejecutar();
        return File(a.Contenido, a.TipoContenido, a.NombreArchivo);
    }

    /// <summary>Analiza el Excel (multipart: archivo, idCliente, idOs). No guarda nada: el front aplica el resultado (Fusionar / Reemplazar).</summary>
    [RequierePermiso("os_guardar")]
    [HttpPost("importar/analizar")]
    [HttpPost("importacion/analizar")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> AnalizarImportacion(IFormFile? archivo, [FromForm] long idCliente, [FromForm] long? idOs, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el archivo Excel."));
        if (idOs is > 0 && await SiNoEsOm(idOs, null, null, ct) is { } error) return error;
        await using var contenido = archivo.OpenReadStream();
        return Responder(await analizarImportacion.EjecutarAsync(contenido, archivo.FileName, archivo.Length, idCliente, idOs, IdUsuarioActual, ct));
    }
}
