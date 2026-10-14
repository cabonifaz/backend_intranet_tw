using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Expediente Digital: bandeja (HU-29), detalle, workflow y exportaciones (HU-30), repositorio de documentos (HU-31),
/// bloqueos y excepciones (HU-32), historial y reasignación (HU-33) y avance de etapa (HU-34).
/// </summary>
[ApiController]
[Authorize]
[Route("api/expedientes")]
public class ExpedientesController(
    ObtenerBandejaExpedientesCasoDeUso        obtenerBandeja,
    ObtenerDetalleExpedienteCasoDeUso         obtenerDetalle,
    ObtenerWorkflowExpedienteCasoDeUso        obtenerWorkflow,
    ExportarWorkflowExpedienteCasoDeUso       exportarWorkflow,
    ExportarExpedienteCasoDeUso               exportarExpediente,
    ObtenerDocumentosExpedienteCasoDeUso      obtenerDocumentos,
    ObtenerArchivoExpedienteCasoDeUso         obtenerArchivo,
    AdjuntarDocumentoExpedienteCasoDeUso      adjuntarDocumento,
    RegistrarBloqueoExpedienteCasoDeUso       registrarBloqueo,
    PrepararResolucionBloqueoCasoDeUso        prepararResolucion,
    ResolverBloqueoExpedienteCasoDeUso        resolverBloqueo,
    ObtenerHistorialExpedienteCasoDeUso       obtenerHistorial,
    ExportarHistorialExpedienteCasoDeUso      exportarHistorial,
    PrepararReasignacionExpedienteCasoDeUso   prepararReasignacion,
    BuscarResponsablesExpedienteCasoDeUso     buscarResponsables,
    ReasignarResponsableExpedienteCasoDeUso   reasignar,
    PrepararAvanceExpedienteCasoDeUso         prepararAvance,
    AvanzarEtapaExpedienteCasoDeUso           avanzar) : ControllerBase
{
    /// <summary>25 MB del documento + margen para el resto del multipart.</summary>
    private const long TamanoMaximoDocumento = AdjuntarDocumentoExpedienteCasoDeUso.TamanoMaximoBytes + 1024 * 1024;

    /// <summary>10 MB de la evidencia + margen.</summary>
    private const long TamanoMaximoEvidencia = ResolverBloqueoExpedienteCasoDeUso.TamanoMaximoBytes + 1024 * 1024;

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

    // ── HU-29 ────────────────────────────────────────────────────────────────

    /// <summary>
    /// HU-29 — Bandeja: tarjetas (activos, listos para avanzar, bloqueados, con excepción, SLA vencidos, pendientes de cierre),
    /// filas (N.° expediente, cliente/RUC, RQ, propuesta, OC, OS/OM, tipo de servicio, etapa, estado, SLA) y las opciones de
    /// los filtros. ?estado=&amp;etapa=&amp;idCliente=&amp;area=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// </summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaExpedientesDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    // ── HU-30 ────────────────────────────────────────────────────────────────

    /// <summary>HU-30 — Detalle: resumen, indicador de etapas, bloqueos y excepciones abiertos, validaciones de la etapa y actividad reciente.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}")]
    public async Task<IActionResult> Detalle(long idExpediente, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Workflow: detalle de gestión por etapa (responsable, tiempos, SLA y resultado), alerta de bloqueo y eventos.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/workflow")]
    public async Task<IActionResult> Workflow(long idExpediente, CancellationToken ct = default)
        => Responder(await obtenerWorkflow.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Descarga el workflow en Excel (.xlsx).</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/workflow/xlsx")]
    public async Task<IActionResult> ExportarWorkflow(long idExpediente, CancellationToken ct = default)
        => Archivo(await exportarWorkflow.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-30 — Descarga el expediente completo (.zip): expediente.xlsx y los documentos por carpeta.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/exportar")]
    public async Task<IActionResult> ExportarExpediente(long idExpediente, CancellationToken ct = default)
    {
        var r = await exportarExpediente.EjecutarAsync(idExpediente, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje));
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    // ── HU-31 ────────────────────────────────────────────────────────────────

    /// <summary>HU-31 — Documentos del expediente (por categoría), tipos que se pueden adjuntar, etapas y visibilidades.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/documentos")]
    public async Task<IActionResult> Documentos(long idExpediente, CancellationToken ct = default)
        => Responder(await obtenerDocumentos.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-31 — Ver (inline) o descargar (?descargar=true) un documento por su clave (ej. doc-12, prop-5, ssoma-3).</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/documentos/{clave}")]
    public async Task<IActionResult> Descargar(long idExpediente, string clave, [FromQuery] bool descargar = false, CancellationToken ct = default)
    {
        var r = await obtenerArchivo.EjecutarAsync(idExpediente, clave, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return r.IdTipoMensaje == 1 ? NotFound(new RespuestaDto<object>(1, r.Mensaje)) : StatusCode(500, new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje));

        var disposicion = new ContentDispositionHeaderValue(descargar ? "attachment" : "inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: !descargar);
    }

    /// <summary>
    /// HU-31 — Adjuntar documento interno (multipart/form-data): idTipoDocumento, etapa, nombre, descripcion, idVisibilidad
    /// y el archivo en el campo "archivo" (PDF, DOCX, XLSX, PNG o JPG, máx. 25 MB).
    /// </summary>
    [RequierePermiso("expediente_documento_adjuntar")]
    [HttpPost("{idExpediente:long}/documentos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoDocumento)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoDocumento)]
    public async Task<IActionResult> Adjuntar(long idExpediente, [FromForm] AdjuntarDocumentoExpedienteDto datos, IFormFile? archivo,
                                              CancellationToken ct = default)
    {
        await using var contenido = archivo?.OpenReadStream();
        return Responder(await adjuntarDocumento.EjecutarAsync(
            idExpediente, datos, contenido, archivo?.FileName, archivo?.Length ?? 0, IdUsuarioActual, ct));
    }

    // ── HU-32 ────────────────────────────────────────────────────────────────

    /// <summary>
    /// HU-32 — Registrar a mano un bloqueo o una excepción. Body: { clase: bloqueo|excepcion, tipo, idMotivo, descripcion,
    /// tipoDocumental, impacto, critico, idResponsable }.
    /// </summary>
    [RequierePermiso("expediente_resolver_bloqueo")]
    [HttpPost("{idExpediente:long}/bloqueos")]
    public async Task<IActionResult> RegistrarBloqueo(long idExpediente, [FromBody] RegistrarBloqueoExpedienteDto datos, CancellationToken ct = default)
        => Responder(await registrarBloqueo.EjecutarAsync(idExpediente, datos, IdUsuarioActual, ct));

    /// <summary>HU-32 — Datos del modal "Resolver bloqueo" o "Cerrar excepción" (contexto y opciones del select).</summary>
    [RequierePermiso("expediente_resolver_bloqueo")]
    [HttpGet("{idExpediente:long}/bloqueos/{idBloqueador:long}/resolucion")]
    public async Task<IActionResult> PrepararResolucion(long idExpediente, long idBloqueador, CancellationToken ct = default)
        => Responder(await prepararResolucion.EjecutarAsync(idExpediente, idBloqueador, IdUsuarioActual, ct));

    /// <summary>
    /// HU-32 — Resolver el bloqueo o cerrar la excepción (multipart/form-data): idOpcion (tipo de resolución o resultado de
    /// cierre), sustento (obligatorio en excepciones) y la evidencia en el campo "archivo" (PDF, JPG o PNG, máx. 10 MB).
    /// </summary>
    [RequierePermiso("expediente_resolver_bloqueo")]
    [HttpPost("{idExpediente:long}/bloqueos/{idBloqueador:long}/resolver")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoEvidencia)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoEvidencia)]
    public async Task<IActionResult> Resolver(long idExpediente, long idBloqueador, [FromForm] ResolverBloqueoExpedienteDto datos,
                                              IFormFile? archivo, CancellationToken ct = default)
    {
        await using var contenido = archivo?.OpenReadStream();
        return Responder(await resolverBloqueo.EjecutarAsync(
            idExpediente, idBloqueador, datos, contenido, archivo?.FileName, archivo?.Length ?? 0, IdUsuarioActual, ct));
    }

    // ── HU-33 ────────────────────────────────────────────────────────────────

    /// <summary>HU-33 — Historial cronológico. ?tipoEvento=&amp;idUsuario=&amp;etapa=&amp;desde=yyyy-MM-dd&amp;hasta=yyyy-MM-dd</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/historial")]
    public async Task<IActionResult> Historial(long idExpediente, [FromQuery] FiltrosHistorialExpedienteDto filtros, CancellationToken ct = default)
        => Responder(await obtenerHistorial.EjecutarAsync(idExpediente, filtros, IdUsuarioActual, ct));

    /// <summary>HU-33 — Descarga el historial (con los mismos filtros) en Excel. Queda registrado en la auditoría.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/historial/xlsx")]
    public async Task<IActionResult> ExportarHistorial(long idExpediente, [FromQuery] FiltrosHistorialExpedienteDto filtros, CancellationToken ct = default)
        => Archivo(await exportarHistorial.EjecutarAsync(idExpediente, filtros, IdUsuarioActual, ct));

    /// <summary>HU-33 — Datos del modal "Reasignar responsable": responsable actual, SLA restante, motivos y nota de impacto.</summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpGet("{idExpediente:long}/reasignacion")]
    public async Task<IActionResult> PrepararReasignacion(long idExpediente, CancellationToken ct = default)
        => Responder(await prepararReasignacion.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-33 — Buscar el nuevo responsable. ?busqueda=</summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpGet("{idExpediente:long}/reasignacion/candidatos")]
    public async Task<IActionResult> Candidatos(long idExpediente, [FromQuery] string? busqueda, CancellationToken ct = default)
        => Responder(await buscarResponsables.EjecutarAsync(idExpediente, busqueda, IdUsuarioActual, ct));

    /// <summary>HU-33 — Reasignar. Body: { idNuevoResponsable, idMotivo, comentario, gestionSla: mantener|reiniciar }.</summary>
    [RequierePermiso("expediente_reasignar")]
    [HttpPost("{idExpediente:long}/reasignar")]
    public async Task<IActionResult> Reasignar(long idExpediente, [FromBody] ReasignarResponsableExpedienteDto datos, CancellationToken ct = default)
        => Responder(await reasignar.EjecutarAsync(idExpediente, datos, IdUsuarioActual, ct));

    // ── HU-34 ────────────────────────────────────────────────────────────────

    /// <summary>HU-34 — Panel de avance: validaciones de la etapa, siguiente etapa y área, y si se puede avanzar.</summary>
    [RequierePermiso("expediente_bandeja")]
    [HttpGet("{idExpediente:long}/avance")]
    public async Task<IActionResult> PrepararAvance(long idExpediente, CancellationToken ct = default)
        => Responder(await prepararAvance.EjecutarAsync(idExpediente, IdUsuarioActual, ct));

    /// <summary>HU-34 — Avanzar a la siguiente etapa. Body opcional: { comentario }.</summary>
    [RequierePermiso("expediente_avanzar")]
    [HttpPost("{idExpediente:long}/avanzar")]
    public async Task<IActionResult> Avanzar(long idExpediente,
        [FromBody(EmptyBodyBehavior = Microsoft.AspNetCore.Mvc.ModelBinding.EmptyBodyBehavior.Allow)] AvanzarEtapaExpedienteDto? datos, CancellationToken ct = default)
        => Responder(await avanzar.EjecutarAsync(idExpediente, datos, IdUsuarioActual, ct));
}
