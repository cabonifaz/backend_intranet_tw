using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-22 Registro y HU-23 Bandeja y Detalle de las Órdenes de Compra recibidas del cliente.</summary>
[ApiController]
[Authorize]
public class OrdenesCompraController(
    PrepararOrdenCompraCasoDeUso          preparar,
    CalcularCoberturaOrdenCompraCasoDeUso calcularCobertura,
    RegistrarOrdenCompraCasoDeUso         registrar,
    ObtenerPdfOrdenCompraCasoDeUso        obtenerPdf,
    ObtenerBandejaOrdenesCompraCasoDeUso      obtenerBandeja,
    ObtenerDetalleOrdenCompraCasoDeUso        obtenerDetalle,
    ObtenerPropuestasSinOrdenCompraCasoDeUso  obtenerPropuestasSinOc) : ControllerBase
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

    /// <summary>HU-22 — Ver o descargar el PDF de una orden de compra (cualquier usuario activo).</summary>
    [HttpGet("api/crm/ordenes-compra/{idOc:long}/pdf")]
    public async Task<IActionResult> ObtenerPdf(long idOc, CancellationToken ct = default)
    {
        var r = await obtenerPdf.EjecutarAsync(idOc, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje), noEncontradoComo404: true);

        var disposicion = new ContentDispositionHeaderValue("inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: true);
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
}
