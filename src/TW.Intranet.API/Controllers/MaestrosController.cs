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
    ObtenerCatalogoCasoDeUso      obtenerCatalogoCasoDeUso,
    ObtenerSedesPorClienteCasoDeUso    obtenerSedesPorClienteCasoDeUso,
    GuardarSedeCasoDeUso               guardarSedeCasoDeUso,
    CambiarEstadoSedeCasoDeUso         cambiarEstadoSedeCasoDeUso,
    ObtenerContactosPorClienteCasoDeUso obtenerContactosPorClienteCasoDeUso,
    GuardarContactoCasoDeUso            guardarContactoCasoDeUso,
    CambiarEstadoContactoCasoDeUso      cambiarEstadoContactoCasoDeUso) : ControllerBase
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

    // ── Sedes ─────────────────────────────────────────────────────────────────

    /// <summary>Devuelve las sedes activas de un cliente.</summary>
    [HttpGet("clientes/{idCliente:long}/sedes")]
    public async Task<IActionResult> ObtenerSedes(long idCliente, CancellationToken ct)
    {
        var respuesta = await obtenerSedesPorClienteCasoDeUso.EjecutarAsync(idCliente, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => NotFound(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Crea o actualiza una sede. IdSede = 0 para nueva sede.</summary>
    [HttpPost("sedes")]
    public async Task<IActionResult> GuardarSede(
        [FromBody] GuardarSedeDto dto, CancellationToken ct)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState);

        var respuesta = await guardarSedeCasoDeUso.EjecutarAsync(dto, UsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Activa o desactiva una sede.</summary>
    [HttpPatch("sedes/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoSede(
        long id, [FromBody] CambiarEstadoSedeDto dto, CancellationToken ct)
    {
        if (id != dto.IdSede)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        var respuesta = await cambiarEstadoSedeCasoDeUso.EjecutarAsync(dto, UsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    // ── Contactos ─────────────────────────────────────────────────────────────

    /// <summary>Devuelve los contactos de un cliente.</summary>
    [HttpGet("clientes/{idCliente:long}/contactos")]
    public async Task<IActionResult> ObtenerContactos(long idCliente, CancellationToken ct)
    {
        var respuesta = await obtenerContactosPorClienteCasoDeUso.EjecutarAsync(idCliente, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => NotFound(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Crea o actualiza un contacto. IdContacto = 0 para nuevo.</summary>
    [HttpPost("contactos")]
    public async Task<IActionResult> GuardarContacto(
        [FromBody] GuardarContactoDto dto, CancellationToken ct)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState);

        var respuesta = await guardarContactoCasoDeUso.EjecutarAsync(dto, UsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Activa o desactiva un contacto.</summary>
    [HttpPatch("contactos/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoContacto(
        long id, [FromBody] CambiarEstadoContactoDto dto, CancellationToken ct)
    {
        if (id != dto.IdContacto)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        var respuesta = await cambiarEstadoContactoCasoDeUso.EjecutarAsync(dto, UsuarioActual, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
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
