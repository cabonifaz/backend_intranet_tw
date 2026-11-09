using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-10 — Ensayos y Calibración: lecturas de pesaje y excentricidad, error crítico y llamada al encargado.</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/equipos/{idOsEquipo:long}/ensayos")]
public class EnsayosMovilController(
    ObtenerEnsayosMovilCasoDeUso            obtener,
    GuardarEnsayosMovilCasoDeUso            guardar,
    RegistrarLlamadaEnsayoMovilCasoDeUso    llamar,
    ILogger<EnsayosMovilController>         logger) : ControladorAppMovil(logger)
{
    /// <summary>Especificaciones del equipo (unidad, clase, capacidad, d, e), lecturas guardadas con su error, EMP y conformidad, y el encargado del área. Exige las variables ambientales guardadas.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>
    /// Guarda las lecturas (solo carga e indicación: el servidor calcula error, EMP y conformidad). Finalizar cierra la etapa; con error crítico exige un motivo
    /// ("Guardar de todas formas"), que avisa al encargado. Devuelve los ensayos actualizados.
    /// </summary>
    [HttpPut]
    [RequestSizeLimit(32 * 1024)]
    public async Task<IActionResult> Guardar(long idOs, long idOsEquipo, [FromBody] GuardarEnsayosMovilDto? d, CancellationToken ct)
        => Responder(await guardar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Registra la llamada al encargado del área en el ensayo y devuelve su nombre y teléfono.</summary>
    [HttpPost("llamada")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Llamar(long idOs, long idOsEquipo, [FromBody] PeticionLlamadaEnsayoMovilDto? d, CancellationToken ct)
        => Responder(await llamar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));
}
