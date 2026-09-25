using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
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
    GuardarRequerimientoCasoDeUso         guardarRequerimientoCasoDeUso
) : ControllerBase
{
    [HttpGet("requerimientos")]
    public async Task<IActionResult> ObtenerRequerimientos(
        [FromQuery] string? estado,
        [FromQuery] string? busqueda,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 10,
        CancellationToken ct = default)
    {
        var respuesta = await obtenerRequerimientosCasoDeUso.EjecutarAsync(
            estado, busqueda, pagina, porPagina, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

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

    [HttpPost("requerimientos")]
    public async Task<IActionResult> GuardarRequerimiento(
        [FromBody] GuardarRequerimientoComandoDto comando,
        CancellationToken ct = default)
    {
        var idUsuarioClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        long.TryParse(idUsuarioClaim, out long idUsuario);

        var respuesta = await guardarRequerimientoCasoDeUso.EjecutarAsync(comando, idUsuario, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }
}
