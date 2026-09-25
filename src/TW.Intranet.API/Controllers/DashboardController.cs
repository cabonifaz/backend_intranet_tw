using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class DashboardController(
    ObtenerResumenDashboardCasoDeUso   resumenCasoDeUso,
    ObtenerAlertasOperativasCasoDeUso  alertasCasoDeUso) : ControllerBase
{
    /// <summary>Devuelve los KPIs operativos del dashboard principal.</summary>
    [HttpGet("resumen")]
    public async Task<IActionResult> ObtenerResumen(CancellationToken ct)
    {
        var respuesta = await resumenCasoDeUso.EjecutarAsync(ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }

    /// <summary>Devuelve las alertas operativas activas.</summary>
    [HttpGet("alertas")]
    public async Task<IActionResult> ObtenerAlertas(CancellationToken ct)
    {
        var respuesta = await alertasCasoDeUso.EjecutarAsync(ct);

        return respuesta.IdTipoMensaje switch
        {
            2 => Ok(respuesta),
            1 => BadRequest(respuesta),
            _ => StatusCode(500, respuesta),
        };
    }
}
