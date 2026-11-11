using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-20 — Reloj marcador de jornada del técnico: inicio de labores, refrigerio, salida de planta y fin de labores, en orden estricto. Cada marcación
/// guarda hora, GPS y puntualidad, y deja al técnico visible en el mapa del Seguimiento Operativo de la intranet; mientras la jornada está en curso la app envía
/// su posición y, si no se mueve por 10 min, Jefatura recibe la alerta «Sin movimiento». El usuario sale siempre del token.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/jornada")]
public class JornadaMovilController(
    ObtenerJornadaMovilCasoDeUso             obtener,
    MarcarJornadaMovilCasoDeUso              marcar,
    RegistrarUbicacionJornadaMovilCasoDeUso  ubicacion,
    ILogger<JornadaMovilController>          logger) : ControladorAppMovil(logger)
{
    /// <summary>La jornada de hoy: estado, el único paso habilitado, horario programado, marcaciones y (finalizada) el resumen.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Body: { tipo, latitud, longitud, precisionMetros?, marcadoEn?, sinConexion? }. Reenviar una marcación ya registrada no duplica nada.</summary>
    [HttpPost("marcaciones")]
    [RequestSizeLimit(2048)]
    public async Task<IActionResult> Marcar([FromBody] MarcarJornadaDto? dto, CancellationToken ct)
        => Responder(await marcar.EjecutarAsync(IdUsuarioActual, dto, ct));

    /// <summary>Posición GPS con la jornada en curso. Body: { latitud, longitud, precisionMetros?, velocidadKmh?, altitudM? }. Máx. una posición cada 10 s.</summary>
    [HttpPost("ubicacion")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> RegistrarUbicacion([FromBody] RegistrarUbicacionDto? dto, CancellationToken ct)
        => Responder(await ubicacion.EjecutarAsync(IdUsuarioActual, dto, ct));
}
