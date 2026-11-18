using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile — Notificaciones push: la app registra el token de su teléfono al iniciar sesión y lo da de baja al cerrarla. El usuario sale del
/// token de sesión (nadie registra teléfonos a nombre de otro).
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/push")]
public class PushMovilController(
    RegistrarDispositivoPushMovilCasoDeUso registrar,
    QuitarDispositivoPushMovilCasoDeUso    quitar,
    ILogger<PushMovilController>           logger) : ControladorAppMovil(logger)
{
    /// <summary>Registra (o actualiza) el token de Expo Push del teléfono del usuario.</summary>
    [RequestSizeLimit(4 * 1024)]
    [HttpPost("dispositivo")]
    public async Task<IActionResult> Registrar([FromBody] RegistrarDispositivoPushEntradaDto entrada, CancellationToken ct)
        => Responder(await registrar.EjecutarAsync(IdUsuarioActual, entrada, ct));

    /// <summary>Da de baja el teléfono (cierre de sesión): deja de recibir avisos.</summary>
    [HttpDelete("dispositivo/{idDispositivo}")]
    public async Task<IActionResult> Quitar(string idDispositivo, CancellationToken ct)
        => Responder(await quitar.EjecutarAsync(IdUsuarioActual, idDispositivo, ct));
}
