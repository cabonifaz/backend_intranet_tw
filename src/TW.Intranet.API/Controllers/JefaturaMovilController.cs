using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-28 — Menú de Jefatura (Jefe de Metrología; el Jefe de Servicio Técnico usa el menú de campo).</summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura")]
public class JefaturaMovilController(
    ObtenerMenuJefaturaMovilCasoDeUso  obtenerMenu,
    ILogger<JefaturaMovilController>   logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// Resumen del día del área del jefe que inició sesión (sale del token): programados, en ruta, en ejecución, con demora y
    /// aprobaciones pendientes, filtrados por el área según la RQ. Quien no es jefe de un área recibe 400.
    /// </summary>
    [HttpGet("menu")]
    public async Task<IActionResult> ObtenerMenu(CancellationToken ct)
        => Responder(await obtenerMenu.EjecutarAsync(IdUsuarioActual, ct));
}
