using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-33 — Revisión de informes técnicos del Jefe de Área. La misma bandeja de Revisión Técnica de la intranet (permisos rt_bandeja para ver y rt_revisar para observar o aprobar),
/// con el alcance de la app: Gerencia, Operaciones, Administración, TI, SSOMA, Calidad y Comercial (cualquier rol) y Administradores ven todo; el Supervisor de Servicio Técnico / Metrología, solo su área.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura/informes")]
public class InformesRevisionMovilController(
    ObtenerInformesRevisionMovilCasoDeUso        obtener,
    ObtenerInformeRevisionMovilCasoDeUso         obtenerDetalle,
    ObtenerArchivoEvidenciaInformeMovilCasoDeUso obtenerArchivo,
    ObservarInformeMovilCasoDeUso                observar,
    AprobarInformeMovilCasoDeUso                 aprobar,
    ILogger<InformesRevisionMovilController>     logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// "Informes por revisar": KPIs (pendientes, observados, sin evidencias, SLA vencido) sobre todo el alcance y la lista de la pestaña
    /// (grupo = por_revisar | en_correccion | aprobados; por defecto por_revisar) con búsqueda por informe, OS, cliente, técnico o equipo (hasta 80 caracteres).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Obtener([FromQuery] string? grupo, [FromQuery] string? busqueda, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, grupo, busqueda, ct));

    /// <summary>"Revisar informe": diagnóstico, validaciones, evidencias (las forzadas resaltadas), corrección pedida y catálogos del modal "Observar informe".</summary>
    [HttpGet("{idInforme:long}")]
    public async Task<IActionResult> ObtenerDetalle(long idInforme, CancellationToken ct)
        => Responder(await obtenerDetalle.EjecutarAsync(IdUsuarioActual, idInforme, ct));

    /// <summary>Archivo de una evidencia del informe (foto o video; con ?cuadro=true, la miniatura del video).</summary>
    [HttpGet("{idInforme:long}/evidencias/{idEvidencia:long}/archivo")]
    public async Task<IActionResult> Archivo(long idInforme, long idEvidencia, [FromQuery] bool cuadro, CancellationToken ct)
    {
        var a = await obtenerArchivo.EjecutarAsync(IdUsuarioActual, idInforme, idEvidencia, cuadro, ct);
        if (a.Contenido is null) return NotFound(new RespuestaDto<object>(1, a.Mensaje ?? "Archivo no encontrado."));
        Response.Headers.CacheControl = "private, no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return File(a.Contenido, a.Tipo!, enableRangeProcessing: true);
    }

    /// <summary>
    /// Observa el informe: { motivo, secciones[], instruccion (10 a 1000 caracteres), plazoHoras (4, 24, 48 o 72) }. El informe pasa a "En corrección", el técnico recibe la solicitud
    /// (notificación y push) y queda en el historial del informe.
    /// </summary>
    [HttpPut("{idInforme:long}/observar")]
    [RequestSizeLimit(8 * 1024)]
    public async Task<IActionResult> Observar(long idInforme, [FromBody] ObservarInformeDto? dto, CancellationToken ct)
        => Responder(await observar.EjecutarAsync(IdUsuarioActual, idInforme, dto, ct));

    /// <summary>
    /// "Aprobar y liberar": { nota? (hasta 500) }. Solo con las validaciones obligatorias completas y sin corrección pendiente; es la misma revisión de la intranet: el informe queda
    /// revisado (cerrado e inmutable) y se avisa al técnico y al responsable de la RQ.
    /// </summary>
    [HttpPut("{idInforme:long}/aprobar")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> Aprobar(long idInforme, [FromBody] AprobarInformeDto? dto, CancellationToken ct)
        => Responder(await aprobar.EjecutarAsync(IdUsuarioActual, idInforme, dto, ct));
}
