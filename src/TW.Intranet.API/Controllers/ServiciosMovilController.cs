using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-03 — Agenda de servicios programados del técnico.</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios")]
public class ServiciosMovilController(
    ObtenerServiciosProgramadosMovilCasoDeUso  obtenerProgramados,
    ILogger<ServiciosMovilController>          logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// Servicios del técnico que inició sesión (sale del token: nadie puede pedir los de otro).
    /// filtro: todos | hoy | pendientes | en_ejecucion · busqueda: N° de OS, RQ, OM o cliente (máx. 100).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> ObtenerProgramados(
        [FromQuery] string? filtro, [FromQuery] string? busqueda, CancellationToken ct)
        => Responder(await obtenerProgramados.EjecutarAsync(IdUsuarioActual, filtro, busqueda, ct));
}
