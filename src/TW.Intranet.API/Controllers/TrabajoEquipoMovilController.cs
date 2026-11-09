using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-08 / HU-09 — Trabajo en el equipo (las 5 etapas) y registro de variables ambientales.</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/equipos/{idOsEquipo:long}")]
public class TrabajoEquipoMovilController(
    ObtenerTrabajoEquipoMovilCasoDeUso          obtener,
    GuardarVariablesAmbientalesMovilCasoDeUso   guardarVariables,
    ILogger<TrabajoEquipoMovilController>       logger) : ControladorAppMovil(logger)
{
    /// <summary>Cabecera del equipo (servicio, tipo de orden OS/OM según la RQ, tiempos) y sus 5 etapas con estado. Sin llegada registrada o sin iniciar el equipo responde 400.</summary>
    [HttpGet("trabajo")]
    public async Task<IActionResult> Obtener(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>
    /// HU-09: guarda temperatura (°C) y humedad (%) obligatorias y la procedencia ("N.I" si va vacía). Fecha y hora las pone el servidor.
    /// Habilita Ensayos y Calibración. Devuelve el trabajo actualizado.
    /// </summary>
    [HttpPut("variables-ambientales")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> GuardarVariables(long idOs, long idOsEquipo, [FromBody] PeticionVariablesAmbientalesMovilDto? d, CancellationToken ct)
        => Responder(await guardarVariables.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));
}
