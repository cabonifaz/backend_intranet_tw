using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>Consulta de datos del contribuyente por RUC (OpenRUC + caché local).</summary>
[ApiController]
[Authorize]
public class ConsultaRucController(
    ConsultarRucCasoDeUso          consultarRuc,
    ObtenerUsoConsultaRucCasoDeUso obtenerUso) : ControllerBase
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

    /// <summary>
    /// Razón social, estado, condición y domicilio fiscal del RUC.
    /// Usa la caché si la consulta tiene menos de ConsultaRuc:DiasVigenciaCache días (forzar=true la ignora).
    /// Avisa si el RUC ya está registrado como cliente.
    /// </summary>
    [RequierePermiso("cliente_guardar")]
    [HttpGet("api/maestros/clientes/consulta-ruc/{ruc}")]
    public async Task<IActionResult> Consultar(string ruc, [FromQuery] bool forzar = false, CancellationToken ct = default)
        => Responder(await consultarRuc.EjecutarAsync(ruc, forzar, IdUsuarioActual, ct));

    /// <summary>Consumo de llamadas externas por mes y proveedor (para vigilar límites).</summary>
    [RequierePermiso("consulta_ruc_uso")]
    [HttpGet("api/maestros/consulta-ruc/uso")]
    public async Task<IActionResult> Uso([FromQuery] int meses = 3, CancellationToken ct = default)
        => Responder(await obtenerUso.EjecutarAsync(meses, ct));
}
