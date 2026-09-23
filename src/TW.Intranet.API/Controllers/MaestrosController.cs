using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class MaestrosController(
    ObtenerClientesCasoDeUso      obtenerClientesCasoDeUso,
    ObtenerClientePorIdCasoDeUso  obtenerClientePorIdCasoDeUso,
    GuardarClienteCasoDeUso       guardarClienteCasoDeUso,
    CambiarEstadoClienteCasoDeUso cambiarEstadoCasoDeUso,
    ObtenerCatalogoCasoDeUso      obtenerCatalogoCasoDeUso) : ControllerBase
{
    private string UsuarioActual =>
        User.FindFirstValue(ClaimTypes.Email)
        ?? User.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? "sistema";

    // ── Clientes ──────────────────────────────────────────────────────────────

    /// <summary>Devuelve la lista de clientes con búsqueda y filtro por estado opcionales.</summary>
    [HttpGet("clientes")]
    public async Task<IActionResult> ObtenerClientes(
        [FromQuery] string? busqueda,
        [FromQuery] string? estado,
        CancellationToken ct)
    {
        var respuesta = await obtenerClientesCasoDeUso.EjecutarAsync(busqueda, estado, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Devuelve el detalle completo de un cliente por su identificador.</summary>
    [HttpGet("clientes/{id:long}")]
    public async Task<IActionResult> ObtenerClientePorId(long id, CancellationToken ct)
    {
        var respuesta = await obtenerClientePorIdCasoDeUso.EjecutarAsync(id, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => NotFound(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Crea o actualiza un cliente. IdCliente = 0 para nuevo registro.</summary>
    [HttpPost("clientes")]
    public async Task<IActionResult> GuardarCliente(
        [FromBody] GuardarClienteDto dto,
        CancellationToken ct)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState);

        var respuesta = await guardarClienteCasoDeUso.EjecutarAsync(dto, UsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    // ── Catálogos ─────────────────────────────────────────────────────────────

    /// <summary>Devuelve los items de un catálogo de tabla_maestra por su Descripcion.</summary>
    [HttpGet("catalogos/{descripcion}")]
    public async Task<IActionResult> ObtenerCatalogo(string descripcion, CancellationToken ct)
    {
        var respuesta = await obtenerCatalogoCasoDeUso.EjecutarAsync(descripcion, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => NotFound(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Activa o desactiva un cliente.</summary>
    [HttpPatch("clientes/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoCliente(
        long id,
        [FromBody] CambiarEstadoClienteDto dto,
        CancellationToken ct)
    {
        if (id != dto.IdCliente)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        var respuesta = await cambiarEstadoCasoDeUso.EjecutarAsync(dto, UsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }
}
