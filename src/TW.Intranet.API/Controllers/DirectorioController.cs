using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Directorio interno (#4303) — disponible para TODO usuario con sesión.
/// Verificación de duplicados (#4290) — para los formularios que crean valores nuevos.
/// </summary>
[ApiController]
[Authorize]
public class DirectorioController(
    ObtenerDirectorioCasoDeUso   obtenerDirectorio,
    ObtenerCumpleanosCasoDeUso   obtenerCumpleanos,
    VerificarDuplicadosCasoDeUso verificarDuplicados) : ControllerBase
{
    private IActionResult Responder<T>(RespuestaDto<T> r) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>Contactos del personal activo. Busca por nombre, correo, cargo o anexo; filtro opcional por área.</summary>
    [HttpGet("api/directorio")]
    public async Task<IActionResult> Directorio([FromQuery] string? busqueda, [FromQuery] string? area,
        [FromQuery] int pagina = 1, [FromQuery] int porPagina = 50, CancellationToken ct = default)
        => Responder(await obtenerDirectorio.EjecutarAsync(busqueda, area, pagina, porPagina, ct));

    /// <summary>Cumpleaños del mes (por defecto, el mes actual). Solo día y mes.</summary>
    [HttpGet("api/directorio/cumpleanos")]
    public async Task<IActionResult> Cumpleanos([FromQuery] int? mes, CancellationToken ct = default)
        => Responder(await obtenerCumpleanos.EjecutarAsync(mes, ct));

    /// <summary>
    /// Valores parecidos a lo que se está escribiendo.
    /// campo: tipo_suministro | subtipo | marca | modelo | area_cliente (con idCliente).
    /// Ej.: /api/maestros/similares?campo=subtipo&amp;texto=controlador de temp
    /// </summary>
    [HttpGet("api/maestros/similares")]
    public async Task<IActionResult> Similares([FromQuery] string? campo, [FromQuery] string? texto,
        [FromQuery] long? idCliente, CancellationToken ct = default)
        => Responder(await verificarDuplicados.EjecutarAsync(campo, texto, idCliente, ct));
}
