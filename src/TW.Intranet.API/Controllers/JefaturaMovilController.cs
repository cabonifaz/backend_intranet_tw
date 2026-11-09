using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-28 — Menú de Jefatura único (jefes de área: Servicio Técnico, Metrología, Operaciones…; supervisores y administradores con área).</summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura")]
public class JefaturaMovilController(
    ObtenerMenuJefaturaMovilCasoDeUso  obtenerMenu,
    ILogger<JefaturaMovilController>   logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// Resumen del día para quien inició sesión (sale del token): programados, en ruta, en ejecución, con demora y aprobaciones
    /// pendientes. Metrología se filtra por el área según la RQ. Quien no tiene el menú de Jefatura recibe 400.
    /// </summary>
    [HttpGet("menu")]
    public async Task<IActionResult> ObtenerMenu(CancellationToken ct)
        => Responder(await obtenerMenu.EjecutarAsync(IdUsuarioActual, ct));
}
