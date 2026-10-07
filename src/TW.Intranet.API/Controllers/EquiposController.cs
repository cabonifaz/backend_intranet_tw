using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>HU-88 — Mantenimiento de Equipos del Cliente.</summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class EquiposController(
    ObtenerEquiposClienteCasoDeUso        obtenerEquipos,
    ObtenerEquipoClientePorIdCasoDeUso    obtenerEquipoPorId,
    GuardarEquipoClienteCasoDeUso         guardarEquipo,
    CambiarEstadoEquipoClienteCasoDeUso   cambiarEstadoEquipo) : ControllerBase
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

    /// <summary>Listado paginado con filtros por cliente, sede, clasificación, estado y búsqueda.</summary>
    [HttpGet("equipos-cliente")]
    public async Task<IActionResult> ObtenerEquipos(
        [FromQuery] string? busqueda,
        [FromQuery] long?   idCliente,
        [FromQuery] long?   idSede,
        [FromQuery] string? clasificacion,
        [FromQuery] string? estado,
        [FromQuery] bool    soloVigentesEnServicio = false,
        [FromQuery] int     pagina = 1,
        [FromQuery] int     porPagina = 10,
        CancellationToken ct = default)
        => Responder(await obtenerEquipos.EjecutarAsync(
            busqueda, idCliente, idSede, clasificacion, estado, soloVigentesEnServicio, pagina, porPagina, ct));

    /// <summary>Ficha completa del equipo.</summary>
    [HttpGet("equipos-cliente/{id:long}")]
    public async Task<IActionResult> ObtenerEquipoPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerEquipoPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>Crea (IdEquipo = 0) o edita un equipo del cliente.</summary>
    [RequierePermiso("equipo_guardar")]
    [HttpPost("equipos-cliente")]
    public async Task<IActionResult> GuardarEquipo([FromBody] GuardarEquipoClienteDto dto, CancellationToken ct = default)
        => Responder(await guardarEquipo.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>Activa o desactiva (no elimina) un equipo del cliente.</summary>
    [RequierePermiso("equipo_cambiar_estado")]
    [HttpPatch("equipos-cliente/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoEquipo(
        long id, [FromBody] CambiarEstadoEquipoClienteDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdEquipo)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoEquipo.EjecutarAsync(dto, IdUsuarioActual, ct));
    }
}
