using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-82 / HU-83 / HU-84 — Usuarios y suplencias.
/// Comparte el prefijo /api/maestros con MaestrosController (rutas distintas).
/// </summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class UsuariosController(
    ObtenerUsuariosCasoDeUso             obtenerUsuarios,
    ObtenerUsuarioPorIdCasoDeUso         obtenerUsuarioPorId,
    ObtenerJefesDisponiblesCasoDeUso     obtenerJefes,
    ObtenerSedesOperativasCasoDeUso      obtenerSedesOperativas,
    GuardarUsuarioCasoDeUso              guardarUsuario,
    CambiarEstadoUsuarioCasoDeUso        cambiarEstadoUsuario,
    ObtenerSuplentesCasoDeUso            obtenerSuplentes,
    ObtenerSuplentePorIdCasoDeUso        obtenerSuplentePorId,
    ObtenerSuplenciasPorUsuarioCasoDeUso obtenerSuplenciasPorUsuario,
    GuardarSuplenteCasoDeUso             guardarSuplente,
    CambiarEstadoSuplenteCasoDeUso       cambiarEstadoSuplente) : ControllerBase
{
    // ── Usuario logueado (del token JWT) ──────────────────────────────────────
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    private string CorreoActual =>
        User.FindFirstValue(ClaimTypes.Email) ?? User.FindFirstValue("email") ?? "sistema";

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    // ══════════════════════════════════════════════════════════════════════════
    //  USUARIOS
    // ══════════════════════════════════════════════════════════════════════════

    /// <summary>HU-82 — Listado paginado de usuarios (pestaña "Usuarios").</summary>
    [HttpGet("usuarios")]
    public async Task<IActionResult> ObtenerUsuarios(
        [FromQuery] string? busqueda,
        [FromQuery] string? rol,
        [FromQuery] string? estado,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 20,
        CancellationToken ct = default)
        => Responder(await obtenerUsuarios.EjecutarAsync(busqueda, rol, estado, pagina, porPagina, ct));

    /// <summary>HU-83 — Usuarios con rol de jefatura (combo "Supervisor directo").</summary>
    [HttpGet("usuarios/jefes")]
    public async Task<IActionResult> ObtenerJefes(CancellationToken ct = default)
        => Responder(await obtenerJefes.EjecutarAsync(ct));

    /// <summary>HU-83 — Ficha completa del usuario.</summary>
    [HttpGet("usuarios/{id:long}")]
    public async Task<IActionResult> ObtenerUsuarioPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerUsuarioPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>HU-83 — Sedes operativas (minas, plantas, oficinas) para asignar al usuario.</summary>
    [HttpGet("sedes-operativas")]
    public async Task<IActionResult> ObtenerSedesOperativas(CancellationToken ct = default)
        => Responder(await obtenerSedesOperativas.EjecutarAsync(ct));

    /// <summary>HU-83 — Crea (IdUsuario = 0) o edita un usuario.</summary>
    [HttpPost("usuarios")]
    public async Task<IActionResult> GuardarUsuario([FromBody] GuardarUsuarioDto dto, CancellationToken ct = default)
        => Responder(await guardarUsuario.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>HU-82 — Activa o desactiva un usuario.</summary>
    [HttpPatch("usuarios/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoUsuario(
        long id, [FromBody] CambiarEstadoUsuarioDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdUsuario)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoUsuario.EjecutarAsync(dto, IdUsuarioActual, ct));
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  SUPLENTES
    // ══════════════════════════════════════════════════════════════════════════

    /// <summary>HU-82 / HU-84 — Maestro global de suplencias (pestaña "Suplentes").</summary>
    [HttpGet("suplentes")]
    public async Task<IActionResult> ObtenerSuplentes(
        [FromQuery] string? busqueda,
        [FromQuery] string? estado,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 20,
        CancellationToken ct = default)
        => Responder(await obtenerSuplentes.EjecutarAsync(busqueda, estado, pagina, porPagina, ct));

    /// <summary>HU-84 — Una asignación de suplencia.</summary>
    [HttpGet("suplentes/{id:long}")]
    public async Task<IActionResult> ObtenerSuplentePorId(long id, CancellationToken ct = default)
        => Responder(await obtenerSuplentePorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>HU-83 — Ficha, sección 05: "Suplentes que lo cubren".</summary>
    [HttpGet("suplentes/titular/{idUsuario:long}")]
    public async Task<IActionResult> ObtenerSuplenciasComoTitular(long idUsuario, CancellationToken ct = default)
        => Responder(await obtenerSuplenciasPorUsuario.EjecutarAsync(idUsuario, "titular", ct));

    /// <summary>HU-83 — Ficha, sección 05: "Personas a las que suple" (solo lectura).</summary>
    [HttpGet("suplentes/suplente/{idUsuario:long}")]
    public async Task<IActionResult> ObtenerSuplenciasComoSuplente(long idUsuario, CancellationToken ct = default)
        => Responder(await obtenerSuplenciasPorUsuario.EjecutarAsync(idUsuario, "suplente", ct));

    /// <summary>HU-84 — Crea (IdAsignacion = 0) o edita una suplencia.</summary>
    [HttpPost("suplentes")]
    public async Task<IActionResult> GuardarSuplente([FromBody] GuardarSuplenteDto dto, CancellationToken ct = default)
        => Responder(await guardarSuplente.EjecutarAsync(dto, CorreoActual, ct));

    /// <summary>HU-82 / HU-84 — Activa o desactiva una suplencia.</summary>
    [HttpPatch("suplentes/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoSuplente(
        long id, [FromBody] CambiarEstadoSuplenteDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdAsignacion)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoSuplente.EjecutarAsync(dto, CorreoActual, ct));
    }
}
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-82 / HU-83 / HU-84 — Usuarios y suplencias.
/// Comparte el prefijo /api/maestros con MaestrosController (rutas distintas).
/// </summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class UsuariosController(
    ObtenerUsuariosCasoDeUso             obtenerUsuarios,
    ObtenerUsuarioPorIdCasoDeUso         obtenerUsuarioPorId,
    ObtenerJefesDisponiblesCasoDeUso     obtenerJefes,
    ObtenerSedesOperativasCasoDeUso      obtenerSedesOperativas,
    GuardarUsuarioCasoDeUso              guardarUsuario,
    CambiarEstadoUsuarioCasoDeUso        cambiarEstadoUsuario,
    ObtenerSuplentesCasoDeUso            obtenerSuplentes,
    ObtenerSuplentePorIdCasoDeUso        obtenerSuplentePorId,
    ObtenerSuplenciasPorUsuarioCasoDeUso obtenerSuplenciasPorUsuario,
    GuardarSuplenteCasoDeUso             guardarSuplente,
    CambiarEstadoSuplenteCasoDeUso       cambiarEstadoSuplente) : ControllerBase
{
    // ── Usuario logueado (del token JWT) ──────────────────────────────────────
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    private string CorreoActual =>
        User.FindFirstValue(ClaimTypes.Email) ?? User.FindFirstValue("email") ?? "sistema";

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    // ══════════════════════════════════════════════════════════════════════════
    //  USUARIOS
    // ══════════════════════════════════════════════════════════════════════════

    /// <summary>HU-82 — Listado paginado de usuarios (pestaña "Usuarios").</summary>
    [HttpGet("usuarios")]
    public async Task<IActionResult> ObtenerUsuarios(
        [FromQuery] string? busqueda,
        [FromQuery] string? rol,
        [FromQuery] string? estado,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 20,
        CancellationToken ct = default)
        => Responder(await obtenerUsuarios.EjecutarAsync(busqueda, rol, estado, pagina, porPagina, ct));

    /// <summary>HU-83 — Usuarios con rol de jefatura (combo "Supervisor directo").</summary>
    [HttpGet("usuarios/jefes")]
    public async Task<IActionResult> ObtenerJefes(CancellationToken ct = default)
        => Responder(await obtenerJefes.EjecutarAsync(ct));

    /// <summary>HU-83 — Ficha completa del usuario.</summary>
    [HttpGet("usuarios/{id:long}")]
    public async Task<IActionResult> ObtenerUsuarioPorId(long id, CancellationToken ct = default)
        => Responder(await obtenerUsuarioPorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>HU-83 — Sedes operativas (minas, plantas, oficinas) para asignar al usuario.</summary>
    [HttpGet("sedes-operativas")]
    public async Task<IActionResult> ObtenerSedesOperativas(CancellationToken ct = default)
        => Responder(await obtenerSedesOperativas.EjecutarAsync(ct));

    /// <summary>HU-83 — Crea (IdUsuario = 0) o edita un usuario.</summary>
    [HttpPost("usuarios")]
    public async Task<IActionResult> GuardarUsuario([FromBody] GuardarUsuarioDto dto, CancellationToken ct = default)
        => Responder(await guardarUsuario.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>HU-82 — Activa o desactiva un usuario.</summary>
    [HttpPatch("usuarios/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoUsuario(
        long id, [FromBody] CambiarEstadoUsuarioDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdUsuario)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoUsuario.EjecutarAsync(dto, IdUsuarioActual, ct));
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  SUPLENTES
    // ══════════════════════════════════════════════════════════════════════════

    /// <summary>HU-82 / HU-84 — Maestro global de suplencias (pestaña "Suplentes").</summary>
    [HttpGet("suplentes")]
    public async Task<IActionResult> ObtenerSuplentes(
        [FromQuery] string? busqueda,
        [FromQuery] string? estado,
        [FromQuery] int pagina = 1,
        [FromQuery] int porPagina = 20,
        CancellationToken ct = default)
        => Responder(await obtenerSuplentes.EjecutarAsync(busqueda, estado, pagina, porPagina, ct));

    /// <summary>HU-84 — Una asignación de suplencia.</summary>
    [HttpGet("suplentes/{id:long}")]
    public async Task<IActionResult> ObtenerSuplentePorId(long id, CancellationToken ct = default)
        => Responder(await obtenerSuplentePorId.EjecutarAsync(id, ct), noEncontradoComo404: true);

    /// <summary>HU-83 — Ficha, sección 05: "Suplentes que lo cubren".</summary>
    [HttpGet("suplentes/titular/{idUsuario:long}")]
    public async Task<IActionResult> ObtenerSuplenciasComoTitular(long idUsuario, CancellationToken ct = default)
        => Responder(await obtenerSuplenciasPorUsuario.EjecutarAsync(idUsuario, "titular", ct));

    /// <summary>HU-83 — Ficha, sección 05: "Personas a las que suple" (solo lectura).</summary>
    [HttpGet("suplentes/suplente/{idUsuario:long}")]
    public async Task<IActionResult> ObtenerSuplenciasComoSuplente(long idUsuario, CancellationToken ct = default)
        => Responder(await obtenerSuplenciasPorUsuario.EjecutarAsync(idUsuario, "suplente", ct));

    /// <summary>HU-84 — Crea (IdAsignacion = 0) o edita una suplencia.</summary>
    [HttpPost("suplentes")]
    public async Task<IActionResult> GuardarSuplente([FromBody] GuardarSuplenteDto dto, CancellationToken ct = default)
        => Responder(await guardarSuplente.EjecutarAsync(dto, CorreoActual, ct));

    /// <summary>HU-82 / HU-84 — Activa o desactiva una suplencia.</summary>
    [HttpPatch("suplentes/{id:long}/estado")]
    public async Task<IActionResult> CambiarEstadoSuplente(
        long id, [FromBody] CambiarEstadoSuplenteDto dto, CancellationToken ct = default)
    {
        if (id != dto.IdAsignacion)
            return BadRequest(new RespuestaDto<object>(1, "El identificador de la ruta no coincide con el cuerpo."));

        return Responder(await cambiarEstadoSuplente.EjecutarAsync(dto, CorreoActual, ct));
    }
}
