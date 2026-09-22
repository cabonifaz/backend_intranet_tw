using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AutenticacionController(IniciarSesionCasoDeUso casoDeUso) : ControllerBase
{
    /// <summary>Inicia sesión con correo y contraseña. Devuelve JWT en caso de éxito.</summary>
    [HttpPost("iniciar-sesion")]
    public async Task<IActionResult> IniciarSesion(
        [FromBody] IniciarSesionEntradaDto entrada,
        CancellationToken ct)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState);

        var respuesta = await casoDeUso.EjecutarAsync(entrada, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => Unauthorized(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }
}
