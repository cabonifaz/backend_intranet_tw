using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-06 — Registro de llegada a la planta del cliente validada por GPS (Hard Stop de los objetivos).</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/llegada")]
public class LlegadaMovilController(
    ObtenerLlegadaMovilCasoDeUso    obtener,
    ValidarLlegadaMovilCasoDeUso    validar,
    RegistrarLlegadaMovilCasoDeUso  registrar,
    ILogger<LlegadaMovilController> logger) : ControladorAppMovil(logger)
{
    /// <summary>Contexto de la pantalla: planta esperada, radio permitido, hora programada y la llegada ya registrada. La OS debe ser del técnico del token.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(long idOs, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Compara la ubicación con la planta (solo lectura): habilita o bloquea "Confirmar llegada" en la app.</summary>
    [HttpPost("validar")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Validar(long idOs, [FromBody] PeticionLlegadaMovilDto? d, CancellationToken ct)
        => Responder(await validar.EjecutarAsync(IdUsuarioActual, idOs, d, ct));

    /// <summary>
    /// Registra la llegada (GPS, precisión y hora). Vuelve a evaluar la ubicación: fuera del radio permitido o con precisión baja responde la regla
    /// de negocio y no registra. Repetir el envío responde éxito con la ya registrada.
    /// </summary>
    [HttpPost]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Registrar(long idOs, [FromBody] PeticionLlegadaMovilDto? d, CancellationToken ct)
        => Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, d, ct));
}
