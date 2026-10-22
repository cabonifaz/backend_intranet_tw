using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-02 — Menú principal de la app de campo.</summary>
[ApiController]
[Authorize]
[Route("api/movil/menu")]
public class MenuMovilController(
    ObtenerResumenMenuMovilCasoDeUso  obtenerResumen,
    ILogger<MenuMovilController>      logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// Indicadores del menú del técnico que inició sesión: servicios asignados,
    /// servicios de hoy (Ruta del Día) y el próximo servicio (banner "Próximo Hit").
    /// El técnico sale del token: nadie puede pedir los datos de otro.
    /// </summary>
    [HttpGet("resumen")]
    public async Task<IActionResult> ObtenerResumen(CancellationToken ct)
        => Responder(await obtenerResumen.EjecutarAsync(IdUsuarioActual, ct));
}
