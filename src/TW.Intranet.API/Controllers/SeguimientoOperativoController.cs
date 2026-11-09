using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-51 (Sprint 5) Bandeja de Seguimiento Operativo del Asistente de Seguimiento (Módulo 9): 4 pestañas (Vista Principal, Servicios en
/// Campo, Técnicos Activos, Incidencias del Día) con KPIs, filtros globales y refresco automático cada 30 s (parámetro SEG_REFRESCO_SEGUNDOS).
/// OBSERVACIONAL: solo GET (ver y llamar al técnico por teléfono); no ejecuta cambios. Acceso: seg_bandeja (cada SP vuelve a validarlo).
/// La ETA no se calcula en esta versión: se informa la última ubicación GPS y hace cuántos minutos.
/// </summary>
[ApiController]
[Route("api/operaciones/seguimiento")]
[Authorize]
public class SeguimientoOperativoController(
    ObtenerResumenSeguimientoCasoDeUso    resumen,
    ObtenerServiciosSeguimientoCasoDeUso  servicios,
    ObtenerTecnicosSeguimientoCasoDeUso   tecnicos,
    ObtenerIncidenciasSeguimientoCasoDeUso incidencias,
    ObtenerFiltrosSeguimientoCasoDeUso    filtros,
    ILogger<SeguimientoOperativoController> logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400 (filtro inválido o sin permiso). Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Seguimiento operativo: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo cargar el seguimiento operativo. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>KPIs + pestaña 1 Vista Principal: mapa operativo, alertas críticas y próximos hitos esperados.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Resumen([FromQuery] ConsultaSeguimientoDto q, CancellationToken ct = default)
        => Responder(await resumen.EjecutarAsync(q, IdUsuarioActual, ct));

    /// <summary>Pestaña 2 Servicios en Campo. Query: idTecnico, idCliente, estado, zona, busqueda, rango (en_curso|finalizados|sin_iniciar), pagina, tamano.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("servicios")]
    public async Task<IActionResult> Servicios([FromQuery] ConsultaSeguimientoDto q, CancellationToken ct = default)
        => Responder(await servicios.EjecutarAsync(q, IdUsuarioActual, ct));

    /// <summary>Pestaña 3 Técnicos Activos: tarjeta por técnico con sus servicios del día.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("tecnicos")]
    public async Task<IActionResult> Tecnicos([FromQuery] ConsultaSeguimientoDto q, CancellationToken ct = default)
        => Responder(await tecnicos.EjecutarAsync(q, IdUsuarioActual, ct));

    /// <summary>Pestaña 4 Incidencias del Día (cronológico). Query: idTecnico, idCliente, zona, busqueda, tipo (código), impacto (retrasa|detiene).</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("incidencias")]
    public async Task<IActionResult> Incidencias([FromQuery] ConsultaSeguimientoDto q, CancellationToken ct = default)
        => Responder(await incidencias.EjecutarAsync(q, IdUsuarioActual, ct));

    /// <summary>Opciones de los filtros globales: técnicos, clientes y zonas con servicios hoy; estados y tipos de incidencia.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("filtros")]
    public async Task<IActionResult> Filtros(CancellationToken ct = default)
        => Responder(await filtros.EjecutarAsync(IdUsuarioActual, ct));
}
