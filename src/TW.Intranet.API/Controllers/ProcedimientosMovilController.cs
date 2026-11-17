using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-24 — Biblioteca de procedimientos: manuales y guías de calibración aprobados (los que carga Calidad en la intranet),
/// con norma, versión, fecha de actualización e historial; el PDF se ve o se descarga al teléfono para leerlo sin conexión.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/procedimientos")]
public class ProcedimientosMovilController(
    ObtenerBibliotecaProcedimientosMovilCasoDeUso biblioteca,
    ObtenerPdfProcedimientoMovilCasoDeUso         pdf,
    ILogger<ProcedimientosMovilController>        logger) : ControladorAppMovil(logger)
{
    /// <summary>Procedimientos aprobados con PDF; <c>paraServicioHoy</c> marca los de los servicios del día del técnico.</summary>
    [HttpGet]
    public async Task<IActionResult> Listar(CancellationToken ct)
        => Responder(await biblioteca.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>PDF del procedimiento, generado con lo registrado en la intranet (el técnico lo guarda en el teléfono).</summary>
    [HttpGet("{id:long}/pdf")]
    public async Task<IActionResult> ObtenerPdf(long id, CancellationToken ct)
    {
        var r = await pdf.EjecutarAsync(IdUsuarioActual, id, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje), StatusCodes.Status404NotFound);

        var disposicion = new ContentDispositionHeaderValue("inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: true);
    }
}
