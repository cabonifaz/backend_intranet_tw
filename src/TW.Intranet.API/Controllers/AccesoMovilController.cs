using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-01 — Desde la intranet, el jefe asigna el usuario de la app a una persona,
/// ve si tiene una sesión abierta (y en qué equipo) y puede liberarla.
/// </summary>
[ApiController]
[Authorize]
[Route("api/maestros/usuarios/{id:long}")]
public class AccesoMovilController(
    ObtenerAccesoMovilCasoDeUso  obtenerAcceso,
    AsignarAccesoMovilCasoDeUso  asignarAcceso,
    LiberarSesionMovilCasoDeUso  liberarSesion) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>Usuario de la app asignado y sesión vigente (equipo, inicio, vencimiento).</summary>
    [RequierePermiso("usuario_ver")]
    [HttpGet("acceso-movil")]
    public async Task<IActionResult> Obtener(long id, CancellationToken ct)
        => Responder(await obtenerAcceso.EjecutarAsync(id, ct));

    /// <summary>Asigna (habilitar = true) o quita (habilitar = false) el usuario de la app.</summary>
    [RequierePermiso("usuario_guardar")]
    [HttpPut("acceso-movil")]
    public async Task<IActionResult> Asignar(long id, [FromBody] AsignarAccesoMovilDto dto, CancellationToken ct)
        => Responder(await asignarAcceso.EjecutarAsync(id, dto, IdUsuarioActual, ct));

    /// <summary>Cierra la sesión de la app del usuario para que pueda entrar desde otro equipo.</summary>
    [RequierePermiso("usuario_guardar")]
    [HttpDelete("sesion-movil")]
    public async Task<IActionResult> Liberar(long id, CancellationToken ct)
        => Responder(await liberarSesion.EjecutarAsync(id, IdUsuarioActual, ct));
}
