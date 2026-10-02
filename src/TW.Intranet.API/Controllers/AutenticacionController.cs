using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AutenticacionController(
    IniciarSesionCasoDeUso        iniciarSesion,
    CambiarContrasenaCasoDeUso    cambiarContrasena) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    /// <summary>Inicia sesión con correo y contraseña. Devuelve JWT en caso de éxito.</summary>
    [HttpPost("iniciar-sesion")]
    public async Task<IActionResult> IniciarSesion(
        [FromBody] IniciarSesionEntradaDto entrada,
        CancellationToken ct)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState);

        var respuesta = await iniciarSesion.EjecutarAsync(entrada, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => Unauthorized(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>
    /// Cambia la contraseña del usuario autenticado. Verifica la contraseña
    /// actual contra el hash en BD y, si coincide, hashea la nueva y limpia
    /// el flag forzar_cambio_contrasena.
    /// </summary>
    [Authorize]
    [HttpPost("cambiar-contrasena")]
    public async Task<IActionResult> CambiarContrasena(
        [FromBody] CambiarContrasenaDto dto,
        CancellationToken ct)
    {
        if (IdUsuarioActual == 0)
            return Unauthorized(new RespuestaDto<bool>(1, "No se pudo identificar al usuario autenticado."));

        var respuesta = await cambiarContrasena.EjecutarAsync(IdUsuarioActual, dto, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }
}
