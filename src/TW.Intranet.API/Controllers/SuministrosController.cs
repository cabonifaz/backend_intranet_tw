using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-86 — Mantenimiento de Suministros.</summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class SuministrosController(
    ObtenerSuministrosCasoDeUso      obtenerSuministros,
    ObtenerSuministroPorIdCasoDeUso  obtenerSuministroPorId,
    GuardarSuministroCasoDeUso       guardarSuministro,
    CambiarEstadoSuministroCasoDeUso cambiarEstadoSuministro) : ControllerBase
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

    /// <summary>Listado paginado con filtros por clase, tipo, estado y búsqueda.</summary>
    [HttpGet("suministros")]
    public async Task<IActionResult> ObtenerSuministros(
        [FromQuery] string? busqueda,
        [FromQuery] string? clase,
        [FromQuery] string? tipo,
        [FromQuery] string? estado,
        [FromQuery] bool soloEnPropuestas = false,
        [FromQuery] bool excluirServicios = false,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 10,
        CancellationToken ct = default)
        => Responder(await obtenerSuministros.EjecutarAsync(
            busqueda, clase, tipo, estado, soloEnPropuestas, excluirServicios, pagina, porPagina, ct));

    /// <summary>Ficha completa del suministro.</summary>
    [HttpGet("suministros/{id:long}")]
    public async Task<IActionResult> ObtenerSuministroPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerSuministroPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>Crea (IdSuministro = 0) o edita un suministro.</summary>
    [RequierePermiso("suministro_guardar")]
    [HttpPost("suministros")]
    public async Task<IActionResult> GuardarSuministro([FromBody] GuardarSuministroDto dto, CancellationToken ct = default)
        => Responder(await guardarSuministro.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>Activa o desactiva (no elimina) un suministro.</summary>
    [RequierePermiso("suministro_cambiar_estado")]
    [HttpPatch("suministros/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoSuministro(
        long id, [FromBody] CambiarEstadoSuministroDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdSuministro)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoSuministro.EjecutarAsync(dto, IdUsuarioActual, ct));
    }
}
