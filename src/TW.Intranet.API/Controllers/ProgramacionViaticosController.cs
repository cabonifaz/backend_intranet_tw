using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-45 (Sprint 5) Asignación de Viáticos y Rendición de Gastos Operativos (Modelo B: adelanto + rendición), desde el botón
/// [Gestionar Viáticos] del Detalle de la Programación (HU-37), visible solo con la programación PROGRAMADA (confirmada por el cliente).
/// Ver (modal con las 2 pestañas y la referencia de solo lectura del Detalle de OS/OM y el Expediente Digital): prog_bandeja.
/// Asignar, revisar gastos y cerrar la rendición: solo el Jefe (prog_aprobar_reprogramacion). El módulo NO marca "Depositado":
/// lo registra Contabilidad fuera de aquí. Cada SP vuelve a validar el permiso y el estado de la programación.
/// </summary>
[ApiController]
[Route("api/operaciones/programacion/programaciones/{idProgramacion:long}/viaticos")]
[Authorize]
public class ProgramacionViaticosController(
    ObtenerViaticosProgramacionCasoDeUso    obtener,
    GuardarViaticosProgramacionCasoDeUso    guardar,
    RevisarGastoProgramacionCasoDeUso       revisar,
    CerrarRendicionProgramacionCasoDeUso    cerrar,
    ObtenerComprobanteGastoCasoDeUso        obtenerComprobante,
    ILogger<ProgramacionViaticosController> logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400 (regla de negocio o permiso). Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Viáticos de programación: error en {Ruta} (usuario {IdUsuario}): {Detalle}",
                Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo procesar los viáticos de la programación. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>Modal "Gestionar Viáticos": cabecera, técnicos, conceptos, asignación, totales, gastos rendidos, tarjetas y cierre.</summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Obtener(long idProgramacion, CancellationToken ct = default)
        => Responder(await obtener.EjecutarAsync(idProgramacion, IdUsuarioActual, ct));

    /// <summary>
    /// Guardar la asignación completa (tab 1). Body: { version, lineas:[{ idGasto?, idTecnico, idConcepto? | nuevoConcepto?, monto }] }.
    /// Notifica a Contabilidad la lista consolidada de lo pendiente de depósito.
    /// </summary>
    [RequierePermiso("prog_aprobar_reprogramacion")]
    [RequestSizeLimit(16 * 1024)]
    [HttpPut]
    public async Task<IActionResult> Guardar(long idProgramacion, [FromBody] GuardarViaticosDto dto, CancellationToken ct = default)
        => Responder(await guardar.EjecutarAsync(idProgramacion, dto, IdUsuarioActual, ct));

    /// <summary>Aprobar, observar (comentario obligatorio) o rechazar (motivo obligatorio) un gasto rendido (tab 2).</summary>
    [RequierePermiso("prog_aprobar_reprogramacion")]
    [RequestSizeLimit(4 * 1024)]
    [HttpPost("gastos/{idGasto:long}/revision")]
    public async Task<IActionResult> Revisar(long idProgramacion, long idGasto, [FromBody] RevisarGastoDto dto, CancellationToken ct = default)
        => Responder(await revisar.EjecutarAsync(idProgramacion, idGasto, dto, IdUsuarioActual, ct));

    /// <summary>Comprobante de un gasto (modal secundario [Ver imagen/PDF]).</summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet("gastos/{idGasto:long}/comprobante")]
    public async Task<IActionResult> Comprobante(long idProgramacion, long idGasto, CancellationToken ct = default)
        => Responder(await obtenerComprobante.EjecutarAsync(idProgramacion, idGasto, IdUsuarioActual, ct));

    /// <summary>Cerrar la rendición: calcula el saldo final y notifica a Contabilidad. No lee cuerpo: nada del cliente influye en el saldo.</summary>
    [RequierePermiso("prog_aprobar_reprogramacion")]
    [HttpPost("cierre")]
    public async Task<IActionResult> Cerrar(long idProgramacion, CancellationToken ct = default)
        => Responder(await cerrar.EjecutarAsync(idProgramacion, IdUsuarioActual, ct));
}
