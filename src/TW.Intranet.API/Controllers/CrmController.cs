using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using System.Security.Claims;
using Microsoft.Net.Http.Headers;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class CrmController(
    ObtenerRequerimientosCasoDeUso        obtenerRequerimientosCasoDeUso,
    ObtenerCatalogosRequerimientoCasoDeUso obtenerCatalogosCasoDeUso,
    ObtenerRequerimientoPorIdCasoDeUso    obtenerRequerimientoPorIdCasoDeUso,
    GuardarRequerimientoCasoDeUso         guardarRequerimientoCasoDeUso,
    AnularRequerimientoCasoDeUso          anularRequerimientoCasoDeUso,
    SubirAdjuntosRequerimientoCasoDeUso   subirAdjuntosRequerimiento,
    ObtenerAdjuntoRequerimientoCasoDeUso  obtenerAdjuntoRequerimiento,
    EliminarAdjuntoRequerimientoCasoDeUso eliminarAdjuntoRequerimiento
) : ControllerBase
{
    /// <summary>10 archivos de 50 MB + margen para el resto del multipart.</summary>
    private const long TamanoMaximoAdjuntos =
        SubirAdjuntosRequerimientoCasoDeUso.MaximoArchivos * SubirAdjuntosRequerimientoCasoDeUso.TamanoMaximoBytes + 1024 * 1024;

    [RequierePermiso("rq_ver")]
    [HttpGet("requerimientos")]
    public async Task<IActionResult> ObtenerRequerimientos(
        [FromQuery] string? estado,
        [FromQuery] string? busqueda,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 10,
        CancellationToken ct = default)
    {
        if (!TryObtenerIdUsuario(out long idUsuario)) return Unauthorized();
        var rol = User.FindFirstValue("rol") ?? "";

        var respuesta = await obtenerRequerimientosCasoDeUso.EjecutarAsync(
            estado, busqueda, pagina, porPagina, idUsuario, rol, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    [RequierePermiso("rq_ver")]
    [HttpGet("requerimientos/catalogos")]
    public async Task<IActionResult> ObtenerCatalogos(CancellationToken ct = default)
    {
        var respuesta = await obtenerCatalogosCasoDeUso.EjecutarAsync(ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    [RequierePermiso("rq_ver")]
    [HttpGet("requerimientos/{id:long}")]
    public async Task<IActionResult> ObtenerRequerimientoPorId(
        long id, CancellationToken ct = default)
    {
        var respuesta = await obtenerRequerimientoPorIdCasoDeUso.EjecutarAsync(id, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    [RequierePermiso("rq_guardar")]
    [HttpPost("requerimientos")]
    public async Task<IActionResult> GuardarRequerimiento(
        [FromBody] GuardarRequerimientoComandoDto comando,
        CancellationToken ct = default)
    {
        if (!TryObtenerIdUsuario(out long idUsuario)) return Unauthorized();

        var respuesta = await guardarRequerimientoCasoDeUso.EjecutarAsync(comando, idUsuario, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    [RequierePermiso("rq_anular", "rq_anular_con_propuesta")]
    [HttpPatch("requerimientos/{id:long}/anular")]
    public async Task<IActionResult> AnularRequerimiento(
        long id,
        [FromBody] AnularRequerimientoComandoDto comando,
        CancellationToken ct = default)
    {
        if (!TryObtenerIdUsuario(out long idUsuario)) return Unauthorized();
        var rol = User.FindFirstValue("rol") ?? "";

        var respuesta = await anularRequerimientoCasoDeUso.EjecutarAsync(id, comando, idUsuario, rol, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>
    /// Adjuntos del requerimiento (multipart/form-data, campo "archivos"): foto, video, correo (.msg/.eml), PDF,
    /// Office, texto o zip. Hasta 10 por subida, 50 MB cada uno, máximo 20 por RQ. Se sube después de guardar el RQ.
    /// </summary>
    [RequierePermiso("rq_guardar")]
    [HttpPost("requerimientos/{id:long}/adjuntos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoAdjuntos)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoAdjuntos)]
    public async Task<IActionResult> SubirAdjuntos(long id, [FromForm] List<IFormFile>? archivos, CancellationToken ct = default)
    {
        if (!TryObtenerIdUsuario(out long idUsuario)) return Unauthorized();
        var lista = (archivos ?? []).Where(a => a.Length > 0).ToList();
        if (lista.Count == 0)
            return BadRequest(new RespuestaDto<object>(1, "Seleccione al menos un archivo."));

        var streams = new List<Stream>();
        try
        {
            var entradas = new List<SubirAdjuntosRequerimientoCasoDeUso.ArchivoEntrada>();
            foreach (var a in lista)
            {
                var s = a.OpenReadStream();
                streams.Add(s);
                entradas.Add(new(s, a.FileName, a.Length));
            }
            var respuesta = await subirAdjuntosRequerimiento.EjecutarAsync(id, entradas, idUsuario, ct);
            return respuesta.IdTipoMensaje switch
            {
                2 => Ok(respuesta),
                1 => BadRequest(respuesta),
                _ => StatusCode(500, respuesta),
            };
        }
        finally
        {
            foreach (var s in streams) await s.DisposeAsync();
        }
    }

    /// <summary>Ver o descargar un adjunto del requerimiento (inline).</summary>
    [RequierePermiso("rq_ver")]
    [HttpGet("requerimientos/adjuntos/{idDocumento:long}")]
    public async Task<IActionResult> ObtenerAdjunto(long idDocumento, CancellationToken ct = default)
    {
        if (!TryObtenerIdUsuario(out long idUsuario)) return Unauthorized();
        var r = await obtenerAdjuntoRequerimiento.EjecutarAsync(idDocumento, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
        {
            var error = new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje);
            return r.IdTipoMensaje == 1 ? NotFound(error) : StatusCode(500, error);
        }

        var disposicion = new ContentDispositionHeaderValue("inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: true);
    }

    /// <summary>Quita un adjunto del requerimiento. Si el RQ entra a acreditación, no se puede quitar el último.</summary>
    [RequierePermiso("rq_guardar")]
    [HttpDelete("requerimientos/adjuntos/{idDocumento:long}")]
    public async Task<IActionResult> EliminarAdjunto(long idDocumento, CancellationToken ct = default)
    {
        if (!TryObtenerIdUsuario(out long idUsuario)) return Unauthorized();
        var respuesta = await eliminarAdjuntoRequerimiento.EjecutarAsync(idDocumento, idUsuario, ct);
        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    private bool TryObtenerIdUsuario(out long idUsuario)
    {
        var claim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        return long.TryParse(claim, out idUsuario) && idUsuario > 0;
    }
}
