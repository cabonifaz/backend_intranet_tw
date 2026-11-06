using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-25 / HU-26 — Viáticos asignados al programar y gastos rendidos del técnico.</summary>
[ApiController]
[Authorize]
[Route("api/movil/viaticos")]
public class ViaticosMovilController(
    ObtenerViaticosMovilCasoDeUso  obtener,
    ILogger<ViaticosMovilController> logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// Resumen (saldo por rendir y gastos en revisión), viáticos por programación, adelanto por concepto y gastos rendidos
    /// del técnico que inició sesión. El técnico sale del token: nadie puede pedir los de otro.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));
}
