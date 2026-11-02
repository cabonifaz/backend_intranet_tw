using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Cartera de clientes (observación 31/10): el Administrador asigna clientes a los comerciales;
/// el comercial solo consulta los suyos.
/// </summary>
[ApiController]
[Authorize]
public class CarteraClientesController(
    ObtenerCarteraClientesCasoDeUso obtenerCartera,
    AsignarCarteraClientesCasoDeUso asignarCartera) : ControllerBase
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
    /// Clientes con su comercial asignado, total, comerciales (con su cantidad de clientes) y si el usuario puede asignar.
    /// ?idComercial=&amp;busqueda=&amp;asignacion=todos|asignados|sin_asignar&amp;pagina=1&amp;porPagina=20
    /// </summary>
    [RequierePermiso("cartera_asignar", "rq_ver")]
    [HttpGet("api/maestros/clientes/cartera")]
    public async Task<IActionResult> Obtener([FromQuery] FiltrosCarteraClientesDto filtros, CancellationToken ct = default)
        => Responder(await obtenerCartera.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>Asigna los clientes a un comercial (idComercial null/0 = quitar de la cartera). Solo Administrador.</summary>
    [RequierePermiso("cartera_asignar")]
    [HttpPut("api/maestros/clientes/cartera")]
    public async Task<IActionResult> Asignar([FromBody] AsignarCarteraClientesComandoDto comando, CancellationToken ct = default)
        => Responder(await asignarCartera.EjecutarAsync(comando, IdUsuarioActual, ct));
}
