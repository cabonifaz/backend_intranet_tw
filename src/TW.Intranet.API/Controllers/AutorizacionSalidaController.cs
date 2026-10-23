using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Intranet · App Mobile HU-04 — Visto bueno de salida del encargado del área (según la RQ).
/// Jefe de Servicio Técnico / Jefe de Metrología ven y resuelven solo las de su área;
/// Jefe/Coordinador de Operaciones y administradores, todas (lo valida el SP con el usuario del token).
/// El token de la app móvil no tiene acceso a estas rutas.
/// </summary>
[ApiController]
[Authorize]
[Route("api/operaciones")]
public class AutorizacionSalidaController(
    ObtenerAutorizacionesSalidaCasoDeUso obtenerAutorizaciones,
    ResolverAutorizacionSalidaCasoDeUso  resolverAutorizacion) : ControllerBase
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

    /// <summary>Solicitudes de salida de los técnicos. estado: pendiente | aprobada | rechazada | (vacío = todas).</summary>
    [HttpGet("autorizaciones-salida")]
    public async Task<IActionResult> Obtener([FromQuery] string? estado, CancellationToken ct)
        => Responder(await obtenerAutorizaciones.EjecutarAsync(IdUsuarioActual, estado, ct));

    /// <summary>Da (aprobar = true) o niega (aprobar = false, con comentario) el visto bueno de salida de una OS.</summary>
    [HttpPut("ordenes-servicio/{idOs:long}/visto-bueno-salida")]
    public async Task<IActionResult> Resolver(long idOs, [FromBody] ResolverAutorizacionSalidaDto dto, CancellationToken ct)
        => Responder(await resolverAutorizacion.EjecutarAsync(IdUsuarioActual, idOs, dto, ct));
}
