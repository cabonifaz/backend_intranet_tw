using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Órdenes de compra recibidas del cliente (Sprint 4, refinamiento HU-22 a HU-28): bandeja, registro con lectura
/// del PDF por IA, validación OC ↔ propuestas, detalle, modal de validación IA, timeline, OC autogenerada y anulación.
/// </summary>
[ApiController]
[Authorize]
public class OrdenesCompraController(
    IOptions<Microsoft.AspNetCore.Mvc.JsonOptions> opcionesJson,
    ObtenerBandejaOrdenesCompraCasoDeUso     obtenerBandeja,
    ObtenerDetalleOrdenCompraCasoDeUso       obtenerDetalle,
    ObtenerValidacionOrdenCompraCasoDeUso    obtenerValidacion,
    ObtenerTimelineOrdenCompraCasoDeUso      obtenerTimeline,
    ExportarTimelineOrdenCompraCasoDeUso     exportarTimeline,
    ObtenerPdfOrdenCompraCasoDeUso           obtenerPdf,
    PrepararOrdenCompraCasoDeUso             preparar,
    PrepararEdicionOrdenCompraCasoDeUso      prepararEdicion,
    ObtenerPropuestasDisponiblesOcCasoDeUso  obtenerDisponibles,
    ExtraerOrdenCompraCasoDeUso              extraer,
    CompararOrdenCompraCasoDeUso             comparar,
    RegistrarOrdenCompraCasoDeUso            registrar,
    EditarOrdenCompraCasoDeUso               editar,
    ReemplazarDocumentoOrdenCompraCasoDeUso  reemplazarDocumento,
    RevalidarOrdenCompraCasoDeUso            revalidar,
    AutogenerarOrdenCompraCasoDeUso          autogenerar,
    PrepararAnulacionOrdenCompraCasoDeUso    prepararAnulacion,
    AnularOrdenCompraCasoDeUso               anular) : ControllerBase
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

    /// <summary>Lee el campo JSON de un multipart (ej. "solicitud") con las mismas opciones que el resto de la API.</summary>
    private bool LeerJson<T>(string? texto, string campo, out T? valor, out IActionResult? error) where T : class
    {
        valor = null; error = null;
        if (string.IsNullOrWhiteSpace(texto)) return true;
        try
        {
            valor = JsonSerializer.Deserialize<T>(texto, opcionesJson.Value.JsonSerializerOptions);
            return true;
        }
        catch (JsonException)
        {
            error = BadRequest(new RespuestaDto<object>(1, $"El campo \"{campo}\" no es un JSON válido."));
            return false;
        }
    }

    // ══════════════════════ Bandeja y consultas ══════════════════════

    /// <summary>
    /// Bandeja: tarjetas (registradas en el mes, validadas, parcial u observadas, OC autogeneradas pendientes, sin asignar),
    /// monto validado del mes por moneda, filas y opciones de filtro.
    /// ?estado=todas|autogenerada|validada|validada_parcial|observada|pendiente_reemplazo|anulada|sin_asignar
    /// &amp;idCliente=&amp;idResponsable=&amp;idPropuesta=&amp;fechaDesde=&amp;fechaHasta=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// &amp;incluirReemplazadas=false (true = muestra también las OC ya reemplazadas, para auditoría)
    /// </summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra")]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaOrdenesCompraDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>
    /// Propuestas aceptadas con saldo por cubrir. Sin idCliente: selector de "+ Nueva OC". Con idCliente (e idOc al editar):
    /// "Agregar propuesta vinculada". incluirConAutogenerada=true en la ficha de registro de la OC real: también trae
    /// las propuestas cubiertas por su OC-AUTO (que se da de baja sola al registrar).
    /// </summary>
    [HttpGet("api/crm/ordenes-compra/propuestas-disponibles")]
    public async Task<IActionResult> PropuestasDisponibles([FromQuery] long? idCliente, [FromQuery] long? idOc,
                                                           [FromQuery] string? busqueda,
                                                           [FromQuery] bool incluirConAutogenerada = false,
                                                           CancellationToken ct = default)
        => Responder(await obtenerDisponibles.EjecutarAsync(idCliente, idOc, busqueda, incluirConAutogenerada, IdUsuarioActual, ct));

    /// <summary>Detalle: cabecera con datos extraídos, propuestas vinculadas con su validación, diferencias y acciones permitidas.</summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}")]
    public async Task<IActionResult> Detalle(long idOc, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>Modal "Detalle de Validación IA" de una propuesta vinculada (?idPropuesta=; por defecto la primera).</summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/validacion")]
    public async Task<IActionResult> Validacion(long idOc, [FromQuery] long? idPropuesta, CancellationToken ct = default)
        => Responder(await obtenerValidacion.EjecutarAsync(idOc, idPropuesta, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>Timeline de la OC (categorías validacion_ia, comercial y documental).</summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/auditoria")]
    public async Task<IActionResult> Timeline(long idOc, CancellationToken ct = default)
        => Responder(await obtenerTimeline.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>Descargar el timeline en XLSX (la descarga queda registrada).</summary>
    [RequierePermiso("oc_bandeja")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/auditoria/xlsx")]
    public async Task<IActionResult> TimelineXlsx(long idOc, CancellationToken ct = default)
        => Archivo(await exportarTimeline.EjecutarAsync(idOc, IdUsuarioActual, ct), descargar: true);

    /// <summary>Ver (inline) o descargar (?descargar=true) el PDF vigente de la OC.</summary>
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/pdf")]
    public async Task<IActionResult> ObtenerPdf(long idOc, [FromQuery] bool descargar = false, CancellationToken ct = default)
        => Archivo(await obtenerPdf.EjecutarAsync(idOc, IdUsuarioActual, ct), descargar);

    // ══════════════════════ Ficha ══════════════════════

    /// <summary>
    /// Ficha de registro: propuesta de origen, OC a reemplazar (?idOcReemplaza=: autogenerada o pendiente_reemplazo), otras propuestas del cliente,
    /// monedas, condiciones de pago y si la extracción con IA está disponible.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpGet("api/crm/propuestas/{idPropuesta:long}/orden-compra/preparar")]
    public async Task<IActionResult> Preparar(long idPropuesta, [FromQuery] long? idOcReemplaza, CancellationToken ct = default)
        => Responder(await preparar.EjecutarAsync(idPropuesta, idOcReemplaza, IdUsuarioActual, ct));

    /// <summary>Ficha en modo edición: datos guardados, vinculaciones (con su nueva versión si la hay) y catálogos.</summary>
    [RequierePermiso("oc_editar")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/edicion")]
    public async Task<IActionResult> PrepararEdicion(long idOc, CancellationToken ct = default)
        => Responder(await prepararEdicion.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>
    /// Lectura del PDF con IA (multipart: "archivo"). Devuelve los datos para precargar la ficha; no guarda nada.
    /// Si la IA no está configurada o falla responde 400 con el mensaje y la ficha se llena a mano.
    /// </summary>
    [HttpPost("api/crm/ordenes-compra/extraer")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Extraer(IFormFile? archivo, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el PDF de la orden de compra."));
        await using var contenido = archivo.OpenReadStream();
        return Responder(await extraer.EjecutarAsync(contenido, IdUsuarioActual, ct));
    }

    /// <summary>
    /// Validación en vivo (no guarda): { idOc | idPropuesta, idOcReemplaza, datos, vinculaciones, decision }.
    /// ?conIa=true agrega la evaluación de conceptos con la IA (usar al pulsar "Validar", no en cada cambio).
    /// </summary>
    [HttpPost("api/crm/ordenes-compra/comparar")]
    public async Task<IActionResult> Comparar([FromBody] CompararOrdenCompraSolicitudDto solicitud, [FromQuery] bool conIa = false,
                                              CancellationToken ct = default)
        => Responder(await comparar.EjecutarAsync(solicitud, conIa, IdUsuarioActual, ct));

    // ══════════════════════ Guardado ══════════════════════

    /// <summary>
    /// Registrar la OC (multipart): "solicitud" = JSON { idOcReemplaza, datos, vinculaciones, decision } y "archivo" = PDF
    /// (máx. 10 MB). decision: validar | observar | correccion_cliente | nueva_version.
    /// </summary>
    [RequierePermiso("oc_registrar")]
    [HttpPost("api/crm/propuestas/{idPropuesta:long}/orden-compra")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Registrar(long idPropuesta, [FromForm] string? solicitud, IFormFile? archivo, CancellationToken ct = default)
    {
        if (!LeerJson<RegistrarOrdenCompraSolicitudDto>(solicitud, "solicitud", out var datos, out var error)) return error!;
        if (datos is null) return BadRequest(new RespuestaDto<object>(1, "Envíe los datos de la orden de compra en el campo \"solicitud\"."));
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el PDF de la orden de compra."));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await registrar.EjecutarAsync(idPropuesta, datos, contenido, archivo.FileName, IdUsuarioActual, ct));
    }

    /// <summary>"Generar OC automáticamente" (el cliente no emite OC): OC-AUTO por el 100% de la propuesta, sin PDF.</summary>
    [RequierePermiso("oc_registrar")]
    [HttpPost("api/crm/propuestas/{idPropuesta:long}/orden-compra/autogenerar")]
    public async Task<IActionResult> Autogenerar(long idPropuesta, CancellationToken ct = default)
        => Responder(await autogenerar.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));

    /// <summary>
    /// Editar la OC (multipart): "solicitud" = JSON { datos, vinculaciones, decision, tipoPdf, motivoPdf } y, opcional,
    /// "archivo" = PDF nuevo (tipoPdf: reemplazo | oc_corregida; motivoPdf obligatorio).
    /// </summary>
    [RequierePermiso("oc_editar")]
    [HttpPut("api/crm/ordenes-compra/{idOc:long}")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Editar(long idOc, [FromForm] string? solicitud, IFormFile? archivo, CancellationToken ct = default)
    {
        if (!LeerJson<EditarOrdenCompraSolicitudDto>(solicitud, "solicitud", out var datos, out var error)) return error!;
        if (datos is null) return BadRequest(new RespuestaDto<object>(1, "Envíe los datos de la orden de compra en el campo \"solicitud\"."));

        if (archivo is null || archivo.Length == 0)
            return Responder(await editar.EjecutarAsync(idOc, datos, null, null, IdUsuarioActual, ct));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await editar.EjecutarAsync(idOc, datos, contenido, archivo.FileName, IdUsuarioActual, ct));
    }

    /// <summary>
    /// Cambiar solo el PDF (multipart): "tipo" = reemplazo | oc_corregida, "motivo" (mín. 5), "archivo" = PDF y, opcional
    /// para oc_corregida, "datos" = JSON con los datos corregidos (de /extraer): las propuestas conformes pasan a validadas.
    /// </summary>
    [RequierePermiso("oc_documento_reemplazar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/documento")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> ReemplazarDocumento(long idOc, [FromForm] string? tipo, [FromForm] string? motivo,
                                                         [FromForm] string? datos, IFormFile? archivo, CancellationToken ct = default)
    {
        if (!LeerJson<DatosOrdenCompraDto>(datos, "datos", out var datosOc, out var error)) return error!;
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el nuevo PDF de la orden de compra."));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await reemplazarDocumento.EjecutarAsync(idOc, tipo, motivo, datosOc, contenido, archivo.FileName,
                                                                 IdUsuarioActual, ct));
    }

    /// <summary>Re-validar con reglas e IA: { idPropuesta } (null = todas las propuestas vinculadas).</summary>
    [RequierePermiso("oc_validar")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/revalidar")]
    public async Task<IActionResult> Revalidar(long idOc, [FromBody] RevalidarOrdenCompraSolicitudDto? solicitud, CancellationToken ct = default)
        => Responder(await revalidar.EjecutarAsync(idOc, solicitud?.IdPropuesta, IdUsuarioActual, ct));

    // ══════════════════════ Anulación ══════════════════════

    /// <summary>Modal de anulación: impacto (propuestas y saldos, OS en ejecución) y motivos.</summary>
    [RequierePermiso("oc_anular")]
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/anulacion")]
    public async Task<IActionResult> PrepararAnulacion(long idOc, CancellationToken ct = default)
        => Responder(await prepararAnulacion.EjecutarAsync(idOc, IdUsuarioActual, ct), noEncontradoComo404: true);

    /// <summary>Anular: { idMotivo, justificacion (mín. 20), confirmaImpacto }. Libera el saldo de las propuestas.</summary>
    [RequierePermiso("oc_anular")]
    [HttpPost("api/crm/ordenes-compra/{idOc:long}/anular")]
    public async Task<IActionResult> Anular(long idOc, [FromBody] AnularOrdenCompraSolicitudDto solicitud, CancellationToken ct = default)
        => Responder(await anular.EjecutarAsync(idOc, solicitud, IdUsuarioActual, ct));
}
