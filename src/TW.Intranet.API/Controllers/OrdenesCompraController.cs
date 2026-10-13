using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>Órdenes de Compra recibidas del cliente: registro y edición (HU-22/24), bandeja y detalle (HU-23), documento y auditoría (HU-25), validación y observación (HU-26), distribución de saldo y OC complementaria (HU-27), liberación para programación (HU-28).</summary>
[ApiController]
[Authorize]
public class OrdenesCompraController(
    PrepararOrdenCompraCasoDeUso          preparar,
    CalcularCoberturaOrdenCompraCasoDeUso calcularCobertura,
    RegistrarOrdenCompraCasoDeUso         registrar,
    ObtenerPdfOrdenCompraCasoDeUso        obtenerPdf,
    ObtenerBandejaOrdenesCompraCasoDeUso      obtenerBandeja,
    ObtenerDetalleOrdenCompraCasoDeUso        obtenerDetalle,
    ObtenerPropuestasSinOrdenCompraCasoDeUso  obtenerPropuestasSinOc,
    EvaluarOrdenCompraCasoDeUso               evaluar,
    PrepararEdicionOrdenCompraCasoDeUso       prepararEdicion,
    EditarOrdenCompraCasoDeUso                editar,
    ObtenerDocumentosOrdenCompraCasoDeUso        obtenerDocumentos,
    ObtenerVersionDocumentoOrdenCompraCasoDeUso  obtenerVersion,
    ReemplazarDocumentoOrdenCompraCasoDeUso      reemplazarDocumento,
    ObtenerAuditoriaOrdenCompraCasoDeUso         obtenerAuditoria,
    ExportarAuditoriaOrdenCompraCasoDeUso        exportarAuditoria,
    PrepararValidacionOrdenCompraCasoDeUso       prepararValidacion,
    ValidarOrdenCompraCasoDeUso                  validar,
    ObservarOrdenCompraCasoDeUso                 observar,
    PrepararDistribucionOrdenCompraCasoDeUso     prepararDistribucion,
    DistribuirOrdenCompraCasoDeUso               distribuir,
    PrepararOcComplementariaCasoDeUso            prepararComplementaria,
    RegistrarOcComplementariaCasoDeUso           registrarComplementaria,
    PrepararLiberacionOrdenCompraCasoDeUso       prepararLiberacion,
    LiberarOrdenCompraCasoDeUso                  liberar) : ControllerBase
{
    /// <summary>10 MB del PDF + margen para el resto del multipart.</summary>
    private const long TamanoMaximoPeticion = RegistrarOrdenCompraCasoDeUso.TamanoMaximoBytes + 1024 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>
    /// HU-22 — Datos del modal: propuesta aceptada (cliente, RQ, monto y moneda para la cobertura),
    /// monedas y vigencia sugerida. Falla si la propuesta no está aceptada o ya tiene OC.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpGet("api/crm/propuestas/{idPropuesta:long}/orden-compra/preparar")]
    public async Task<IActionResult> Preparar(long idPropuesta, CancellationToken ct = default)
        => Responder(await preparar.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));

    /// <summary>
    /// HU-22 — Indicador de cobertura (sin guardar): { numeroOc, fechaOc, fechaRecepcion, idMoneda, monto, vigenciaDias }.
    /// Responde completa | parcial | excede | moneda_diferente con el % y la diferencia.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpPost("api/crm/propuestas/{idPropuesta:long}/orden-compra/cobertura")]
    public async Task<IActionResult> Cobertura(long idPropuesta, [FromBody] DatosOrdenCompraDto datos, CancellationToken ct = default)
        => Responder(await calcularCobertura.EjecutarAsync(idPropuesta, datos, IdUsuarioActual, ct));

    /// <summary>
    /// HU-22 — Registrar la OC (multipart/form-data): numeroOc, fechaOc, fechaRecepcion, idMoneda, monto,
    /// vigenciaDias, observaciones y el PDF obligatorio en el campo "archivo" (máx. 10 MB).
    /// Queda en 'pendiente_validacion' y se notifica a Contabilidad y Operaciones.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpPost("api/crm/propuestas/{idPropuesta:long}/orden-compra")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Registrar(long idPropuesta, [FromForm] DatosOrdenCompraDto datos,
                                               IFormFile? archivo, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el PDF de la orden de compra."));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await registrar.EjecutarAsync(
            idPropuesta, datos, contenido, archivo.FileName, archivo.Length, IdUsuarioActual, ct));
    }

    /// <summary>HU-22 — Ver (inline) o descargar (?descargar=true) el PDF vigente de la OC. HU-25: cada acceso queda registrado.</summary>
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/pdf")]
    public async Task<IActionResult> ObtenerPdf(long idOc, [FromQuery] bool descargar = false, CancellationToken ct = default)
        => Archivo(await obtenerPdf.EjecutarAsync(idOc, IdUsuarioActual, ct), descargar);

    /// <summary>Devuelve el archivo: inline (previsualizar) o attachment (descargar=true).</summary>
    private IActionResult Archivo(RespuestaDto<ArchivoDescargaDto> r, bool descargar)
    {
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje), noEncontradoComo404: true);

        var disposicion = new ContentDispositionHeaderValue(descargar ? "attachment" : "inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: !descargar);
    }

    /// <summary>
    /// HU-23 — Bandeja de órdenes de compra: tarjetas (vigentes, cobertura parcial, saldo insuficiente,
    /// pendientes de validación, listas para programación, observadas), filas con monto OC, monto aplicado,
    /// saldo, cobertura y estado, y opciones de los filtros de cliente y responsable.
    /// ?estado=&amp;cobertura=&amp;idCliente=&amp;idResponsable=&amp;fechaDesde=&amp;fechaHasta=&amp;conPdf=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// </summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra")]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaOrdenesCompraDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>
    /// HU-23 — Propuestas aceptadas sin orden de compra (selector del botón "+ Nueva Orden de Compra").
    /// Con la propuesta elegida se usan los endpoints de registro de la HU-22.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpGet("api/crm/ordenes-compra/propuestas-pendientes")]
    public async Task<IActionResult> PropuestasPendientes([FromQuery] string? busqueda, CancellationToken ct = default)
        => Responder(await obtenerPropuestasSinOc.EjecutarAsync(busqueda, IdUsuarioActual, ct));

    /// <summary>
    /// HU-23 — Detalle de la orden de compra: datos generales, cobertura económica (propuesta vs. OC),
    /// aplicaciones, checklist de validación, vinculaciones (RQ, propuesta, expediente, OS), documentos,
    /// workflow e historial.
    /// </summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}")]
    public async Task<IActionResult> Detalle(long idOc, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>
    /// HU-24 — Panel "Validación de Cobertura" y "Checklist de negocio" en tiempo real al REGISTRAR:
    /// { numeroOc, idMoneda, monto, tieneArchivo } (todo opcional). No guarda nada.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpPost("api/crm/propuestas/{idPropuesta:long}/orden-compra/evaluar")]
    public async Task<IActionResult> EvaluarRegistro(long idPropuesta, [FromBody] EvaluacionOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await evaluar.EvaluarRegistroAsync(idPropuesta, datos, IdUsuarioActual, ct));

    /// <summary>
    /// HU-24 — Datos de la pantalla "Editar Orden de Compra": campos editables, propuesta/RQ/cliente bloqueados,
    /// resumen de situación y si cambiar monto o moneda exigirá revalidación.
    /// </summary>
    [RequierePermiso("oc_editar")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/edicion")]
    public async Task<IActionResult> PrepararEdicion(long idOc, CancellationToken ct = default)
        => Responder(await prepararEdicion.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>HU-24 — Panel en tiempo real al EDITAR (incluye requiereRevalidacion y cambioBloqueado).</summary>
    [RequierePermiso("oc_editar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/evaluar")]
    public async Task<IActionResult> EvaluarEdicion(long idOc, [FromBody] EvaluacionOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await evaluar.EvaluarEdicionAsync(idOc, datos, IdUsuarioActual, ct));

    /// <summary>
    /// HU-24 — Guardar la edición (multipart/form-data): numeroOc, referencia, fechaOc, fechaRecepcion, idMoneda,
    /// monto, vigenciaDias, observaciones, revalidar (true = "Guardar y revalidar") y opcionalmente un PDF nuevo
    /// en "archivo". Cambiar monto o moneda de una OC validada la regresa a validación.
    /// </summary>
    [RequierePermiso("oc_editar")]
    [HttpPut("api/crm/ordenes-compra/{idOc:long}")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Editar(long idOc, [FromForm] EditarOrdenCompraSolicitudDto datos,
                                            IFormFile? archivo, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return Responder(await editar.EjecutarAsync(idOc, datos, null, null, 0, IdUsuarioActual, ct));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await editar.EjecutarAsync(
            idOc, datos, contenido, archivo.FileName, archivo.Length, IdUsuarioActual, ct));
    }

    /// <summary>HU-25 — Modal "Documento de Orden de Compra": documento actual e historial de versiones.</summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/documentos")]
    public async Task<IActionResult> Documentos(long idOc, CancellationToken ct = default)
        => Responder(await obtenerDocumentos.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>
    /// HU-25 — Reemplazar el PDF (multipart/form-data): "archivo" (PDF, máx. 10 MB) y "motivo" (5 a 300 caracteres).
    /// Crea una nueva versión; la anterior se conserva en el historial.
    /// </summary>
    [RequierePermiso("oc_documento_reemplazar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/documentos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> ReemplazarDocumento(long idOc, [FromForm] string? motivo, IFormFile? archivo, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el nuevo PDF de la orden de compra."));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await reemplazarDocumento.EjecutarAsync(
            idOc, motivo, contenido, archivo.FileName, archivo.Length, IdUsuarioActual, ct));
    }

    /// <summary>HU-25 — Ver (inline) o descargar (?descargar=true) una versión del PDF. Cada acceso queda registrado.</summary>
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/documentos/{idDocumento:long}")]
    public async Task<IActionResult> VersionDocumento(long idOc, long idDocumento, [FromQuery] bool descargar = false, CancellationToken ct = default)
        => Archivo(await obtenerVersion.EjecutarAsync(idOc, idDocumento, IdUsuarioActual, ct), descargar);

    /// <summary>
    /// HU-25 — Historial de Expediente Industrial: cabecera, timeline inmutable de eventos críticos (RQ, expediente,
    /// propuesta, visto bueno, envío, aceptación, OC, documentos, validación y OS), registro de auditoría del CRM,
    /// aplicaciones relacionadas y documentación SSOMA.
    /// </summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/auditoria")]
    public async Task<IActionResult> Auditoria(long idOc, CancellationToken ct = default)
        => Responder(await obtenerAuditoria.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>HU-25 — Descargar el historial completo de auditoría en XLSX (la descarga queda registrada).</summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/auditoria/xlsx")]
    public async Task<IActionResult> AuditoriaXlsx(long idOc, CancellationToken ct = default)
        => Archivo(await exportarAuditoria.EjecutarAsync(idOc, IdUsuarioActual, ct), descargar: true);

    /// <summary>
    /// HU-26 — Modales "Validar" y "Observar": resumen comparativo, checklist (con los ítems a confirmar contra la
    /// OC física), dictamen, motivos tipificados (tal cual), responsables de corrección y observaciones anteriores.
    /// </summary>
    [RequierePermiso("oc_validar")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/validacion")]
    public async Task<IActionResult> PrepararValidacion(long idOc, CancellationToken ct = default)
        => Responder(await prepararValidacion.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>
    /// HU-26 — Validar la OC: { confirmados: ["razon_social","ruc","moneda","monto","pdf_legible"], comentario }.
    /// Exige el checklist automático conforme y todas las confirmaciones. Notifica al responsable y a Operaciones.
    /// </summary>
    [RequierePermiso("oc_validar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/validar")]
    public async Task<IActionResult> Validar(long idOc, [FromBody] ValidarOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await validar.EjecutarAsync(idOc, datos, IdUsuarioActual, ct));

    /// <summary>
    /// HU-26 — Observar la OC: { motivos: [ids], detalle, idResponsable }. Queda OBSERVADA, bloquea la liberación
    /// del expediente y notifica al responsable de corrección.
    /// </summary>
    [RequierePermiso("oc_validar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/observar")]
    public async Task<IActionResult> Observar(long idOc, [FromBody] ObservarOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await observar.EjecutarAsync(idOc, datos, IdUsuarioActual, ct));

    /// <summary>
    /// HU-27 — Modal "Distribuir Monto de OC": monto total, aplicado, saldo disponible y uso de fondos, aplicaciones
    /// registradas y propuestas destino (aceptadas, mismo cliente y moneda, con monto pendiente).
    /// </summary>
    [RequierePermiso("oc_distribuir")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/distribucion")]
    public async Task<IActionResult> PrepararDistribucion(long idOc, CancellationToken ct = default)
        => Responder(await prepararDistribucion.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>HU-27 — Cálculo en tiempo real (sin guardar): { idPropuesta, monto } → saldo de la OC antes y después.</summary>
    [RequierePermiso("oc_distribuir")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/distribucion/evaluar")]
    public async Task<IActionResult> EvaluarDistribucion(long idOc, [FromBody] DistribuirOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await distribuir.EjecutarAsync(idOc, datos, soloValidar: true, IdUsuarioActual, ct));

    /// <summary>
    /// HU-27 — Guardar distribución: { idPropuesta, monto }. El monto no puede exceder el saldo disponible ni lo pendiente
    /// de la propuesta. monto = 0 quita la aplicación (salvo la propuesta principal).
    /// </summary>
    [RequierePermiso("oc_distribuir")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/distribucion")]
    public async Task<IActionResult> Distribuir(long idOc, [FromBody] DistribuirOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await distribuir.EjecutarAsync(idOc, datos, soloValidar: false, IdUsuarioActual, ct));

    /// <summary>
    /// HU-27 — Modal "Registrar OC Complementaria": cobertura actual (propuesta, OC existentes, faltante, %) y el resultado
    /// en tiempo real con ?monto= (OC existente + Nueva OC = Cobertura total).
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpGet("api/crm/propuestas/{idPropuesta:long}/orden-compra-complementaria/preparar")]
    public async Task<IActionResult> PrepararComplementaria(long idPropuesta, [FromQuery] decimal? monto, CancellationToken ct = default)
        => Responder(await prepararComplementaria.EjecutarAsync(idPropuesta, monto, IdUsuarioActual, ct));

    /// <summary>
    /// HU-27 — Registrar la OC complementaria (multipart/form-data): numeroOc, fechaOc, fechaRecepcion, monto,
    /// vigenciaDias (opcional), observaciones, referencia y el PDF obligatorio en "archivo". La moneda es la de la propuesta.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpPost("api/crm/propuestas/{idPropuesta:long}/orden-compra-complementaria")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> RegistrarComplementaria(long idPropuesta, [FromForm] RegistrarOcComplementariaSolicitudDto datos,
                                                             IFormFile? archivo, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el PDF de la orden de compra."));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await registrarComplementaria.EjecutarAsync(
            idPropuesta, datos, contenido, archivo.FileName, archivo.Length, IdUsuarioActual, ct));
    }

    /// <summary>
    /// HU-28 — Modal "Liberar para Programación": validaciones de cumplimiento (propuesta, OC, cobertura, vigencia, SCTR,
    /// SSOMA, bloqueos), impacto, siguiente etapa (Programación), responsable (Operaciones) y SLA estimado.
    /// </summary>
    [RequierePermiso("oc_liberar")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/liberacion")]
    public async Task<IActionResult> PrepararLiberacion(long idOc, CancellationToken ct = default)
        => Responder(await prepararLiberacion.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>
    /// HU-28 — Liberar para programación: { confirmaImpacto, comentario }. Con requisitos pendientes exige confirmaImpacto
    /// (la responsabilidad pasa a Operaciones). Crea o actualiza el expediente y notifica a Operaciones.
    /// </summary>
    [RequierePermiso("oc_liberar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/liberar")]
    public async Task<IActionResult> Liberar(long idOc, [FromBody] LiberarOrdenCompraSolicitudDto datos, CancellationToken ct = default)
        => Responder(await liberar.EjecutarAsync(idOc, datos, IdUsuarioActual, ct));
}
