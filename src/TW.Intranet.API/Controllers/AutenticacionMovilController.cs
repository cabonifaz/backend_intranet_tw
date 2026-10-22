using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-01 — Acceso a la app de campo.
/// Ingreso solo con usuario (asignado por el jefe) y contraseña; 1 equipo a la vez.
/// Para cambiar la contraseña y leer los datos del usuario, la app usa los endpoints
/// existentes: POST api/autenticacion/cambiar-contrasena y GET api/autenticacion/me.
/// Desarrollo seguro: límite de ingresos por IP, bloqueo por intentos fallidos,
/// mismo mensaje para usuario inexistente o contraseña errada, cuerpo máximo de 4 KB.
/// </summary>
[ApiController]
[Route("api/movil/autenticacion")]
public class AutenticacionMovilController(
    IniciarSesionMovilCasoDeUso                  iniciarSesion,
    CerrarSesionMovilCasoDeUso                   cerrarSesion,
    ILogger<AutenticacionMovilController>        logger) : ControladorAppMovil(logger)
{
    /// <summary>Inicia sesión en la app. Devuelve el JWT de la app (claim canal = movil).</summary>
    [AllowAnonymous]
    [EnableRateLimiting(SeguridadAppMovil.PoliticaIngreso)]
    [RequestSizeLimit(4 * 1024)]
    [HttpPost("iniciar-sesion")]
    public async Task<IActionResult> IniciarSesion([FromBody] IniciarSesionMovilEntradaDto entrada, CancellationToken ct)
    {
        var ip = SeguridadAppMovil.IpCliente(HttpContext);
        var r  = await iniciarSesion.EjecutarAsync(entrada, ip, ct);

        if (r.IdTipoMensaje == 2)
            logger.LogInformation("App móvil: ingreso correcto usuario={Usuario} ip={Ip}", SeguridadAppMovil.ParaLog(entrada.Usuario), ip);
        else if (r.IdTipoMensaje == 1)
            logger.LogWarning("App móvil: ingreso rechazado usuario={Usuario} ip={Ip} motivo={Motivo}",
                              SeguridadAppMovil.ParaLog(entrada.Usuario), ip, SeguridadAppMovil.ParaLog(r.Mensaje));

        return Responder(r, StatusCodes.Status401Unauthorized);
    }

    /// <summary>Cierra la sesión de la app en este equipo (queda libre para ingresar desde otro).</summary>
    [Authorize]
    [HttpPost("cerrar-sesion")]
    public async Task<IActionResult> CerrarSesion(CancellationToken ct)
    {
        if (User.FindFirstValue("canal") != "movil")
            return BadRequest(new RespuestaDto<bool>(1, "Este endpoint es solo para la app móvil."));

        var sesionToken = User.FindFirstValue("sesion_token") ?? string.Empty;
        return Responder(await cerrarSesion.EjecutarAsync(IdUsuarioActual, sesionToken, ct));
    }
}
