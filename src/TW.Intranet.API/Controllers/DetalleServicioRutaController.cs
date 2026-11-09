using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-52 (Sprint 5) Detalle del Servicio en Ruta del Asistente de Seguimiento: modal con cabecera fija y pestañas Resumen, Avance por Equipos,
/// Mapa GPS, Timeline del Día, Demoras/Incidencias, Registrar (HU-53) y Cierre del Servicio (HU-54, solo si el servicio está finalizado).
/// OBSERVACIONAL: solo GET. El front vuelve a consultar cada RefrescoSegundos (15 s, parámetro SEG_DETALLE_REFRESCO_SEGUNDOS).
/// Acceso: seg_bandeja (cada SP vuelve a validarlo). Solo servicios de la jornada de hoy; cualquier otro idOs responde 400 sin revelar datos.
/// </summary>
[ApiController]
[Route("api/operaciones/seguimiento/servicios/{idOs:long}")]
[Authorize]
public class DetalleServicioRutaController(
    ObtenerDetalleServicioRutaCasoDeUso        detalle,
    ObtenerAvanceServicioRutaCasoDeUso         avance,
    ObtenerSeccionEquipoServicioRutaCasoDeUso  seccionEquipo,
    ObtenerMapaServicioRutaCasoDeUso           mapa,
    ObtenerTimelineServicioRutaCasoDeUso       timeline,
    ObtenerIncidenciasServicioRutaCasoDeUso    incidencias,
    ExportarIncidenciasServicioRutaCasoDeUso   exportar,
    ObtenerCierreServicioRutaCasoDeUso         cierre,
    ObtenerAuditoriaServicioRutaCasoDeUso      auditoria,
    ObtenerEvidenciaIncidenciaCasoDeUso        evidencia,
    ILogger<DetalleServicioRutaController> logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400. Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Detalle del servicio en ruta: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo cargar el detalle del servicio. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>Cabecera fija + pestaña Resumen (programación, equipos a intervenir, responsables, contacto en planta y métricas rápidas).</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Detalle(long idOs, CancellationToken ct = default)
        => Responder(await detalle.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Pestaña Avance por Equipos: mini-checklist por equipo y chips de conteo.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("avance")]
    public async Task<IActionResult> Avance(long idOs, CancellationToken ct = default)
        => Responder(await avance.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Drill-down de un equipo. seccion: fotos | ensayos | documentos | observaciones | mediciones.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("avance/{idEquipo:long}/{seccion}")]
    public async Task<IActionResult> SeccionEquipo(long idOs, long idEquipo, string seccion, CancellationToken ct = default)
        => Responder(await seccionEquipo.EjecutarAsync(IdUsuarioActual, idOs, idEquipo, seccion, ct));

    /// <summary>Pestaña Mapa GPS: posición actual, ruta del día, pin del cliente con radio de proximidad, panel y cronograma GPS.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("mapa")]
    public async Task<IActionResult> Mapa(long idOs, CancellationToken ct = default)
        => Responder(await mapa.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Pestaña Timeline del Día. Query: categoria (hito|alerta|incidencia|asistente), orden (reciente|antiguo).</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("timeline")]
    public async Task<IActionResult> Timeline(long idOs, [FromQuery] string? categoria, [FromQuery] string? orden, CancellationToken ct = default)
        => Responder(await timeline.EjecutarAsync(IdUsuarioActual, idOs, categoria, orden, ct));

    /// <summary>Pestaña Demoras / Incidencias de esta OS: mini-KPIs y tabla.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("incidencias")]
    public async Task<IActionResult> Incidencias(long idOs, CancellationToken ct = default)
        => Responder(await incidencias.EjecutarAsync(IdUsuarioActual, idOs, null, ct));

    /// <summary>Detalle completo de un registro (clave d&lt;id&gt; demora, i&lt;id&gt; incidencia o a&lt;id&gt; registro del Asistente, HU-53): descripción extendida y foto de evidencia.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("incidencias/{clave}")]
    public async Task<IActionResult> Incidencia(long idOs, string clave, CancellationToken ct = default)
        => Responder(await incidencias.EjecutarAsync(IdUsuarioActual, idOs, string.IsNullOrWhiteSpace(clave) ? "?" : clave, ct));

    /// <summary>
    /// Foto de evidencia de una demora/incidencia/registro del Asistente (la cargada por el técnico desde la app o por el Asistente en HU-53).
    /// Devuelve la imagen (image/jpeg, image/png o image/webp). El front la pide con el token y la muestra como blob.
    /// </summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("incidencias/{clave}/evidencia")]
    public async Task<IActionResult> EvidenciaIncidencia(long idOs, string clave, CancellationToken ct = default)
    {
        var r = await evidencia.EjecutarAsync(IdUsuarioActual, idOs, clave, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(r);
        Response.Headers.CacheControl = "private, no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["Content-Security-Policy"] = "default-src 'none'";
        return File(r.Datos.Contenido, r.Datos.TipoContenido);
    }

    /// <summary>Exporta las demoras/incidencias de la OS a CSV (celdas neutralizadas contra inyección de fórmulas).</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("incidencias/exportar")]
    public async Task<IActionResult> ExportarIncidencias(long idOs, CancellationToken ct = default)
    {
        var r = await exportar.EjecutarAsync(IdUsuarioActual, idOs, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(r);
        Response.Headers.CacheControl = "no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return File(r.Datos.Contenido, "text/csv; charset=utf-8", r.Datos.NombreArchivo);
    }

    /// <summary>
    /// Pestaña condicional Cierre del Servicio (HU-54, observacional): resultado del cierre, equipos con sus 5 estados, acta de conformidad y accesos del pie.
    /// Solo si el servicio está finalizado; si no, 400. Incluye datos del firmante: sin caché ni sniffing.
    /// </summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("cierre")]
    public async Task<IActionResult> Cierre(long idOs, CancellationToken ct = default)
    {
        NoCache();
        return Responder(await cierre.EjecutarAsync(IdUsuarioActual, idOs, ct));
    }

    /// <summary>"Auditoría del servicio" del cierre (HU-54): historial del servicio finalizado (acciones auditadas e hitos). Solo lectura.</summary>
    [RequierePermiso("seg_bandeja")]
    [HttpGet("cierre/auditoria")]
    public async Task<IActionResult> AuditoriaCierre(long idOs, CancellationToken ct = default)
    {
        NoCache();
        return Responder(await auditoria.EjecutarAsync(IdUsuarioActual, idOs, ct));
    }

    private void NoCache()
    {
        Response.Headers.CacheControl = "no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
    }
}
