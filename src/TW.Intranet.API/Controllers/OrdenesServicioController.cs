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
    AnalizarImportacionOsCasoDeUso               analizarImportacion) : ControllerBase
{
    private const long TamanoMaximoPeticion = 6 * 1024 * 1024;

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

    // ══════════════════════ HU-40 Crear / editar / solicitar edición / anular ══════════════════════

    /// <summary>Ficha "Nueva OS/OM" desde una propuesta aceptada: cliente, contactos, contexto de la propuesta, conceptos y equipos sugeridos.</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("preparar")]
    public async Task<IActionResult> Preparar([FromQuery] long idPropuesta, CancellationToken ct = default)
        => Responder(await preparar.EjecutarAsync(idPropuesta, null, IdUsuarioActual, ct));

    /// <summary>Ficha de edición: borrador, o emitida con la edición aprobada por el Jefe Comercial (modo edicion_aprobada).</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("{idOs:long}/edicion")]
    public async Task<IActionResult> PrepararEdicion(long idOs, CancellationToken ct = default)
        => Responder(await preparar.EjecutarAsync(null, idOs, IdUsuarioActual, ct));

    /// <summary>Crea la orden (borrador, o emitida si emitir = true).</summary>
    [RequierePermiso("os_guardar")]
    [HttpPost]
    public async Task<IActionResult> Crear([FromBody] GuardarOrdenServicioDto? datos, CancellationToken ct = default)
        => Responder(await guardar.EjecutarAsync(0, datos, IdUsuarioActual, ct));

    /// <summary>Guarda el borrador / lo emite, o guarda la edición autorizada (re-emite y notifica a Operaciones).</summary>
    [RequierePermiso("os_guardar")]
    [HttpPut("{idOs:long}")]
    public async Task<IActionResult> Actualizar(long idOs, [FromBody] GuardarOrdenServicioDto? datos, CancellationToken ct = default)
        => Responder(await guardar.EjecutarAsync(idOs, datos, IdUsuarioActual, ct));

    /// <summary>Modal "Solicitar edición": a quién se envía (Jefe Comercial) y motivos.</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("{idOs:long}/solicitud-edicion/preparar")]
    public async Task<IActionResult> PrepararSolicitudEdicion(long idOs, CancellationToken ct = default)
        => Responder(await prepararSolicitud.EjecutarAsync(idOs, IdUsuarioActual, ct));

    /// <summary>Envía la solicitud de edición: { idMotivo, comentario (20 a 500) }. Notifica (campanita y correo) al Jefe Comercial.</summary>
    [RequierePermiso("os_guardar")]
    [HttpPost("{idOs:long}/solicitud-edicion")]
    public async Task<IActionResult> SolicitarEdicion(long idOs, [FromBody] SolicitarEdicionOsDto? datos, CancellationToken ct = default)
        => Responder(await solicitarEdicion.EjecutarAsync(idOs, datos, IdUsuarioActual, ct));

    /// <summary>Jefe Comercial: { aprobar, comentario (obligatorio al rechazar, mín. 10) }. Notifica al comercial.</summary>
    [RequierePermiso("os_aprobar_edicion")]
    [HttpPost("solicitudes/{idSolicitud:long}/resolver")]
    public async Task<IActionResult> ResolverSolicitud(long idSolicitud, [FromBody] ResolverSolicitudEdicionOsDto? datos, CancellationToken ct = default)
        => Responder(await resolverSolicitud.EjecutarAsync(idSolicitud, datos, IdUsuarioActual, ct));

    /// <summary>Modal Anular: impacto en la programación (técnico, fecha, viáticos, personal) y motivos.</summary>
    [RequierePermiso("os_anular")]
    [HttpGet("{idOs:long}/anulacion/preparar")]
    public async Task<IActionResult> PrepararAnulacion(long idOs, CancellationToken ct = default)
        => Responder(await prepararAnulacion.EjecutarAsync(idOs, IdUsuarioActual, ct));

    /// <summary>Anula: { idMotivo, comentario (20 a 500) }. Libera personal y viáticos asignados.</summary>
    [RequierePermiso("os_anular")]
    [HttpPost("{idOs:long}/anular")]
    public async Task<IActionResult> Anular(long idOs, [FromBody] AnularOrdenServicioDto? datos, CancellationToken ct = default)
        => Responder(await anular.EjecutarAsync(idOs, datos, IdUsuarioActual, ct));

    // ══════════════════════ HU-42 Detalle (tabs con carga perezosa) ══════════════════════

    /// <summary>Cabecera, tab Resumen, acciones permitidas y Avance por equipos.</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}")]
    public async Task<IActionResult> Detalle(long idOs, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idOs, IdUsuarioActual, ct));

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}/propuesta")]
    public async Task<IActionResult> TabPropuesta(long idOs, CancellationToken ct = default)
        => Responder(await tabs.PropuestaAsync(idOs, IdUsuarioActual, ct));

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}/equipos")]
    public async Task<IActionResult> TabEquipos(long idOs, CancellationToken ct = default)
        => Responder(await tabs.EquiposAsync(idOs, IdUsuarioActual, ct));

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}/conceptos")]
    public async Task<IActionResult> TabConceptos(long idOs, CancellationToken ct = default)
        => Responder(await tabs.ConceptosAsync(idOs, IdUsuarioActual, ct));

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}/observaciones")]
    public async Task<IActionResult> TabObservaciones(long idOs, CancellationToken ct = default)
        => Responder(await tabs.ObservacionesAsync(idOs, IdUsuarioActual, ct));

    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}/programacion")]
    public async Task<IActionResult> TabProgramacion(long idOs, CancellationToken ct = default)
        => Responder(await tabs.ProgramacionAsync(idOs, IdUsuarioActual, ct));

    /// <summary>Solo OM.</summary>
    [RequierePermiso("os_bandeja", "os_bandeja_operaciones")]
    [HttpGet("{idOs:long}/certificado")]
    public async Task<IActionResult> TabCertificado(long idOs, CancellationToken ct = default)
        => Responder(await tabs.CertificadoAsync(idOs, IdUsuarioActual, ct));

    // ══════════════════════ HU-43 Buscadores ══════════════════════

    /// <summary>Equipos del cliente: ?idCliente=&amp;idOs=&amp;busqueda=&amp;clasificacion=equipo|instrumento|pesa&amp;ubicacion=&amp;pagina=1&amp;porPagina=20</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("equipos-cliente")]
    public async Task<IActionResult> BuscarEquipos([FromQuery] FiltrosBuscarEquiposOsDto filtros, CancellationToken ct = default)
        => Responder(await buscarEquipos.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>Conceptos (suministros de clase Servicio): ?busqueda=&amp;tipo=&amp;pagina=1&amp;porPagina=20</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("conceptos")]
    public async Task<IActionResult> BuscarConceptos([FromQuery] FiltrosBuscarConceptosOsDto filtros, CancellationToken ct = default)
        => Responder(await buscarConceptos.EjecutarAsync(filtros, IdUsuarioActual, ct));

    // ══════════════════════ HU-44 Importación por Excel ══════════════════════

    /// <summary>Plantilla oficial (.xlsx): hojas Conceptos y Equipos.</summary>
    [RequierePermiso("os_guardar")]
    [HttpGet("importacion/plantilla")]
    public IActionResult Plantilla()
    {
        var a = plantilla.Ejecutar();
        return File(a.Contenido, a.TipoContenido, a.NombreArchivo);
    }

    /// <summary>Analiza el Excel (multipart: archivo, idCliente, idOs). No guarda nada: el front aplica el resultado (Fusionar / Reemplazar).</summary>
    [RequierePermiso("os_guardar")]
    [HttpPost("importacion/analizar")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> AnalizarImportacion(IFormFile? archivo, [FromForm] long idCliente, [FromForm] long? idOs, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el archivo Excel."));
        await using var contenido = archivo.OpenReadStream();
        return Responder(await analizarImportacion.EjecutarAsync(contenido, archivo.FileName, archivo.Length, idCliente, idOs, IdUsuarioActual, ct));
    }
}
