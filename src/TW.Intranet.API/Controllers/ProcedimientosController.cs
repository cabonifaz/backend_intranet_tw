using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-87 — Mantenimiento de Procedimientos Metrológicos.</summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class ProcedimientosController(
    ObtenerProcedimientosCasoDeUso         obtenerProcedimientos,
    ObtenerProcedimientoPorIdCasoDeUso     obtenerProcedimientoPorId,
    ObtenerProcedimientosOpcionesCasoDeUso obtenerOpciones,
    GuardarProcedimientoCasoDeUso          guardarProcedimiento,
    CambiarEstadoProcedimientoCasoDeUso    cambiarEstadoProcedimiento,
    ObtenerPermisoPdfProcedimientoCasoDeUso obtenerPermisoPdf,
    SubirPdfProcedimientoCasoDeUso         subirPdf,
    ObtenerPdfProcedimientoCasoDeUso       obtenerPdf) : ControllerBase
{
    /// <summary>10 MB del PDF + margen para el resto del multipart.</summary>
    private const long TamanoMaximoPeticion = SubirPdfProcedimientoCasoDeUso.TamanoMaximoBytes + 1024 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    /// <summary>IP de origen (Railway la envía en X-Forwarded-For).</summary>
    private string? IpCliente
    {
        get
        {
            var reenviada = Request.Headers["X-Forwarded-For"].FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(reenviada))
                return reenviada.Split(',')[0].Trim();
            return HttpContext.Connection.RemoteIpAddress?.ToString();
        }
    }

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>Listado paginado con filtros por año, estado y búsqueda.</summary>
    [HttpGet("procedimientos")]
    public async Task<IActionResult> ObtenerProcedimientos(
        [FromQuery] string? busqueda,
        [FromQuery] int? anio,
        [FromQuery] string? estado,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 15,
        CancellationToken ct = default)
        => Responder(await obtenerProcedimientos.EjecutarAsync(busqueda, anio, estado, pagina, porPagina, ct));

    /// <summary>Procedimientos activos como { value, label } para el combo de Suministros (HU-86).</summary>
    [HttpGet("procedimientos/opciones")]
    public async Task<IActionResult> ObtenerOpciones(CancellationToken ct = default)
        => Responder(await obtenerOpciones.EjecutarAsync(ct));

    /// <summary>Ficha completa del procedimiento.</summary>
    [HttpGet("procedimientos/{id:long}")]
    public async Task<IActionResult> ObtenerProcedimientoPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerProcedimientoPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>Crea (IdProcedimiento = 0) o edita. Al editar sube la versión y guarda el historial.</summary>
    [RequierePermiso("procedimiento_guardar")]
    [HttpPost("procedimientos")]
    public async Task<IActionResult> GuardarProcedimiento([FromBody] GuardarProcedimientoDto dto, CancellationToken ct = default)
        => Responder(await guardarProcedimiento.EjecutarAsync(dto, IdUsuarioActual, IpCliente, ct));

    /// <summary>Activa o desactiva (no elimina) un procedimiento.</summary>
    [RequierePermiso("procedimiento_cambiar_estado")]
    [HttpPatch("procedimientos/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoProcedimiento(
        long id, [FromBody] CambiarEstadoProcedimientoDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdProcedimiento)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoProcedimiento.EjecutarAsync(dto, IdUsuarioActual, ct));
    }

    // ── Carga real del PDF aprobado ──────────────────────────────────────────

    /// <summary>
    /// Si el usuario actual puede cargar o reemplazar el PDF aprobado (acción procedimiento_pdf_cargar)
    /// y, con idProcedimiento, si el procedimiento lo admite (no inactivo). Sin id: solo el permiso.
    /// </summary>
    [HttpGet("procedimientos/pdf/permiso")]
    public async Task<IActionResult> ObtenerPermisoPdf([FromQuery] long? idProcedimiento, CancellationToken ct = default)
        => Responder(await obtenerPermisoPdf.EjecutarAsync(idProcedimiento ?? 0, IdUsuarioActual, ct));

    /// <summary>
    /// Carga o reemplaza el PDF aprobado (multipart/form-data, campo "archivo", máx. 10 MB).
    /// Requiere la acción procedimiento_pdf_cargar (módulo "calidad", #4301): área Calidad o administradores.
    /// </summary>
    [RequierePermiso("procedimiento_pdf_cargar")]
    [HttpPost("procedimientos/{id:long}/pdf")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> SubirPdf(long id, [FromForm] IFormFile? archivo, CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Seleccione un archivo PDF."));

        await using var contenido = archivo.OpenReadStream();
        return Responder(await subirPdf.EjecutarAsync(
            id, contenido, archivo.FileName, archivo.Length, IdUsuarioActual, IpCliente, ct));
    }

    /// <summary>Muestra el PDF aprobado (inline). Cualquier usuario autenticado.</summary>
    [HttpGet("procedimientos/{id:long}/pdf")]
    public async Task<IActionResult> ObtenerPdf(long id, CancellationToken ct = default)
    {
        var r = await obtenerPdf.EjecutarAsync(id, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje), noEncontradoComo404: true);

        var disposicion = new ContentDispositionHeaderValue("inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();

        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: true);
    }
}
