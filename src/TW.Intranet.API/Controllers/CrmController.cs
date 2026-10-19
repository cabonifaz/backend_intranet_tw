using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using System.Security.Claims;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class CrmController(
    ObtenerRequerimientosCasoDeUso        obtenerRequerimientosCasoDeUso,
    ObtenerCatalogosRequerimientoCasoDeUso obtenerCatalogosCasoDeUso,
    ObtenerRequerimientoPorIdCasoDeUso    obtenerRequerimientoPorIdCasoDeUso,
    GuardarRequerimientoCasoDeUso         guardarRequerimientoCasoDeUso,
    AnularRequerimientoCasoDeUso          anularRequerimientoCasoDeUso
) : ControllerBase
{
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

    private bool TryObtenerIdUsuario(out long idUsuario)
    {
        var claim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        return long.TryParse(claim, out idUsuario) && idUsuario > 0;
    }
}
