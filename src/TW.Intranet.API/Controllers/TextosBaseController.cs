using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-85 — Mantenimiento de Textos Base.</summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class TextosBaseController(
    ObtenerTextosBaseCasoDeUso      obtenerTextosBase,
    ObtenerTextoBasePorIdCasoDeUso  obtenerTextoBasePorId,
    GuardarTextoBaseCasoDeUso       guardarTextoBase,
    CambiarEstadoTextoBaseCasoDeUso cambiarEstadoTextoBase) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>Listado paginado con filtros por categoría, estado y búsqueda.</summary>
    [HttpGet("textos-base")]
    public async Task<IActionResult> ObtenerTextosBase(
        [FromQuery] string? busqueda,
        [FromQuery] string? tipoCategoria,
        [FromQuery] string? estado,
        [FromQuery] bool soloPredeterminados = false,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 10,
        CancellationToken ct = default)
        => Responder(await obtenerTextosBase.EjecutarAsync(
            busqueda, tipoCategoria, estado, soloPredeterminados, pagina, porPagina, ct));

    /// <summary>Ficha completa de un texto base.</summary>
    [HttpGet("textos-base/{id:long}")]
    public async Task<IActionResult> ObtenerTextoBasePorId(long id, CancellationToken ct = default)
        => Responder(await obtenerTextoBasePorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>Crea (IdTextoBase = 0) o edita. Al editar se guarda la versión anterior.</summary>
    [HttpPost("textos-base")]
    public async Task<IActionResult> GuardarTextoBase([FromBody] GuardarTextoBaseDto dto, CancellationToken ct = default)
        => Responder(await guardarTextoBase.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>Activa o desactiva (no elimina) un texto base.</summary>
    [HttpPatch("textos-base/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoTextoBase(
        long id, [FromBody] CambiarEstadoTextoBaseDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdTextoBase)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoTextoBase.EjecutarAsync(dto, IdUsuarioActual, ct));
    }
}
