using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile / HU-51 — Posición GPS del técnico mientras su servicio está en curso (alimenta la Bandeja de Seguimiento Operativo).
/// Valida que la OS sea del técnico del token (con otra OS responde lo mismo que si no existiera: sin IDOR) y que esté en ruta, en ejecución o en pausa.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/ubicacion")]
public class UbicacionMovilController(RegistrarUbicacionMovilCasoDeUso registrar, ILogger<UbicacionMovilController> logger) : ControladorAppMovil(logger)
{
    /// <summary>Body: { latitud, longitud, precisionMetros? }. Máx. 10 posiciones por minuto y técnico (antirrebote en el SP).</summary>
    [HttpPost]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> Registrar(long idOs, [FromBody] RegistrarUbicacionDto? dto, CancellationToken ct)
        => Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, dto, ct));
}
