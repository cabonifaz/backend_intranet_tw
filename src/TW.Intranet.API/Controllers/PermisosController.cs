using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Roles por niveles + permisos por área (reunión 02-oct).
/// El front usa /api/autenticacion/permisos para armar el menú y habilitar acciones.
/// </summary>
[ApiController]
[Route("api")]
[Authorize]
public class PermisosController(
    ObtenerMisPermisosCasoDeUso      obtenerMisPermisos,
    ObtenerPermisosAreaRolCasoDeUso  obtenerPermisosAreaRol,
    GuardarPermisoCasoDeUso          guardarPermiso,
    ObtenerMisAccionesCasoDeUso      obtenerMisAcciones) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>Permisos del usuario actual: [{ modulo, moduloLabel, areaModulo, acceso, esExcepcion }].</summary>
    [HttpGet("autenticacion/permisos")]
    public async Task<IActionResult> MisPermisos(CancellationToken ct = default)
        => Responder(await obtenerMisPermisos.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Acciones del usuario actual: [{ accion, accionLabel, modulo, nivelRequerido, permitido }].</summary>
    [HttpGet("autenticacion/acciones")]
    public async Task<IActionResult> MisAcciones(CancellationToken ct = default)
        => Responder(await obtenerMisAcciones.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Matriz de un área + rol (ej. ?area=metrologia&amp;rol=usuario).</summary>
    [RequierePermiso("permisos_ver")]
    [HttpGet("maestros/permisos")]
    public async Task<IActionResult> PermisosAreaRol([FromQuery] string? area, [FromQuery] string? rol, CancellationToken ct = default)
        => Responder(await obtenerPermisosAreaRol.EjecutarAsync(area, rol, ct));

    /// <summary>Define una excepción: { area, rol, modulo, acceso }. Acceso vacío = regla general.</summary>
    [RequierePermiso("permisos_guardar")]
    [HttpPut("maestros/permisos")]
    public async Task<IActionResult> Guardar([FromBody] GuardarPermisoDto dto, CancellationToken ct = default)
        => Responder(await guardarPermiso.EjecutarAsync(dto, IdUsuarioActual, ct));
}
