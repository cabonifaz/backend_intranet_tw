using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class NotificacionesController(ObtenerNotificacionesCasoDeUso casoDeUso) : ControllerBase
{
    /// <summary>Devuelve las notificaciones del usuario autenticado.</summary>
    [HttpGet]
    public async Task<IActionResult> ObtenerNotificaciones(CancellationToken ct)
    {
        var subClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!long.TryParse(subClaim, out var idUsuario))
            return Unauthorized();

        var respuesta = await casoDeUso.EjecutarAsync(idUsuario, ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }
}
