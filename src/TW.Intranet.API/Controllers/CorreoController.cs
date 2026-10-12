using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>Servicio de correo: reenvío de credenciales y correo de prueba.</summary>
[ApiController]
[Authorize]
public class CorreoController(
    ReenviarCredencialesCasoDeUso reenviarCredenciales,
    EnviarCorreoPruebaCasoDeUso   enviarPrueba) : ControllerBase
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

    /// <summary>
    /// Genera una nueva contraseña temporal (cambio obligatorio al ingresar) y la envía al correo del usuario.
    /// Si el correo no sale, la respuesta incluye la contraseña para entregarla por otro medio.
    /// </summary>
    [RequierePermiso("usuario_guardar")]
    [HttpPost("api/maestros/usuarios/{id:long}/reenviar-credenciales")]
    public async Task<IActionResult> ReenviarCredenciales(long id, CancellationToken ct = default)
        => Responder(await reenviarCredenciales.EjecutarAsync(id, IdUsuarioActual, ct));

    /// <summary>Envía un correo de prueba para validar la configuración (Correo__ApiKey, remitente).</summary>
    [RequierePermiso("correo_prueba")]
    [HttpPost("api/admin/correo/prueba")]
    public async Task<IActionResult> Prueba([FromBody] EnviarCorreoPruebaDto dto, CancellationToken ct = default)
        => Responder(await enviarPrueba.EjecutarAsync(dto, IdUsuarioActual, ct));
}
