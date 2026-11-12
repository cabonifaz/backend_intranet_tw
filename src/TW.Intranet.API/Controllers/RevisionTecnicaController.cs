using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Servicio Técnico › Revisión de Informes (Sprint 5, HU-56 a HU-59). El Supervisor / Jefe de Servicio Técnico revisa los
/// informes que generan sus técnicos desde la app móvil: los edita, registra la precotización cuando hay observaciones y los
/// marca como revisados (inmutables). Permisos: rt_bandeja (ver), rt_editar (editar y precotizar), rt_revisar (cerrar).
/// Cada SP vuelve a validar el permiso, el alcance (informes de los técnicos de su área) y el estado.
/// </summary>
[ApiController]
[Route("api/servicio-tecnico/informes")]
[Authorize]
public class RevisionTecnicaController(
    ObtenerBandejaInformesCasoDeUso       bandeja,
    ExportarBandejaInformesCasoDeUso      exportar,
    ObtenerDetalleInformeCasoDeUso        detalle,
    GuardarInformeTecnicoCasoDeUso        guardar,
    GuardarPrecotizacionInformeCasoDeUso  guardarPrecotizacion,
    PrepararRevisionInformeCasoDeUso      prepararRevision,
    RegistrarRevisionInformeCasoDeUso     registrarRevision,
    ObtenerHistorialInformeCasoDeUso      historial,
    ObtenerArchivoFotoInformeCasoDeUso    archivoFoto,
    ObtenerViaticosInformeCasoDeUso       viaticos,
    ILogger<RevisionTecnicaController>    logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400. Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Revisión técnica: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo completar la operación. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>HU-56 Bandeja: tarjetas, filas y opciones de filtro. Query: grupo, busqueda, idTecnico, idCliente, conObservaciones,
    /// slaVencido, fechaDesde, fechaHasta, pagina, porPagina.</summary>
    [RequierePermiso("rt_bandeja")]
    [HttpGet]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaInformesDto filtros, CancellationToken ct = default)
        => Responder(await bandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>HU-56 "Exportar": CSV con los mismos filtros (sin paginar).</summary>
    [RequierePermiso("rt_bandeja")]
    [HttpGet("exportar")]
    public async Task<IActionResult> Exportar([FromQuery] FiltrosBandejaInformesDto filtros, CancellationToken ct = default)
    {
        var r = await exportar.EjecutarAsync(filtros, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    /// <summary>HU-57 Detalle: resumen, procedimiento, ensayos, observaciones, recomendaciones, fotos, precotización, historial
    /// reciente y acciones permitidas (sirve también para la pantalla de edición).</summary>
    [RequierePermiso("rt_bandeja")]
    [HttpGet("{idInforme:long}")]
    public async Task<IActionResult> Detalle(long idInforme, CancellationToken ct = default)
        => Responder(await detalle.EjecutarAsync(idInforme, IdUsuarioActual, ct));

    /// <summary>HU-58 "Guardar cambios" (pasos 1 a 4). Secciones opcionales; una lista enviada reemplaza a la anterior.</summary>
    [RequierePermiso("rt_editar")]
    [HttpPut("{idInforme:long}")]
    public async Task<IActionResult> Guardar(long idInforme, [FromBody] GuardarInformeTecnicoDto datos, CancellationToken ct = default)
        => Responder(await guardar.EjecutarAsync(idInforme, datos, IdUsuarioActual, ct));

    /// <summary>HU-58 Paso 4: registrar / actualizar la precotización (queda enviada a Comercial).</summary>
    [RequierePermiso("rt_editar")]
    [HttpPut("{idInforme:long}/precotizacion")]
    public async Task<IActionResult> GuardarPrecotizacion(long idInforme, [FromBody] GuardarPrecotizacionInformeDto datos, CancellationToken ct = default)
        => Responder(await guardarPrecotizacion.EjecutarAsync(idInforme, datos, IdUsuarioActual, ct));

    /// <summary>HU-59 Modal "Registrar Revisión": checklist de cumplimiento e impacto tras el cierre.</summary>
    [RequierePermiso("rt_revisar")]
    [HttpGet("{idInforme:long}/revision")]
    public async Task<IActionResult> PrepararRevision(long idInforme, CancellationToken ct = default)
        => Responder(await prepararRevision.EjecutarAsync(idInforme, IdUsuarioActual, ct));

    /// <summary>HU-59 "Confirmar Revisión": el informe queda revisado e inmutable. Body: { nota }.</summary>
    [RequierePermiso("rt_revisar")]
    [HttpPost("{idInforme:long}/revision")]
    public async Task<IActionResult> RegistrarRevision(long idInforme, [FromBody] RegistrarRevisionInformeDto? datos, CancellationToken ct = default)
        => Responder(await registrarRevision.EjecutarAsync(idInforme, datos, IdUsuarioActual, ct));

    /// <summary>HU-57 Pestaña Fotos: el archivo de una foto del informe (JPEG, o MP4 / con ?cuadro=true su miniatura). Requiere el token en la cabecera Authorization:
    /// el front debe pedirlo con fetch y mostrarlo con URL.createObjectURL (un &lt;img src&gt; directo no envía el token).</summary>
    [RequierePermiso("rt_bandeja")]
    [HttpGet("{idInforme:long}/fotos/{idEvidencia:long}/archivo")]
    public async Task<IActionResult> ArchivoFoto(long idInforme, long idEvidencia, [FromQuery] bool cuadro, CancellationToken ct = default)
    {
        var (contenido, tipo, mensaje) = await archivoFoto.EjecutarAsync(idInforme, idEvidencia, cuadro, IdUsuarioActual, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Foto no encontrada.")) : File(contenido, tipo!, enableRangeProcessing: true);
    }

    /// <summary>HU-57 Viáticos de la OS del informe: asignado, rendido, gastos y cierre de la rendición. Siempre solo lectura.</summary>
    [RequierePermiso("rt_bandeja")]
    [HttpGet("{idInforme:long}/viaticos")]
    public async Task<IActionResult> Viaticos(long idInforme, CancellationToken ct = default)
        => Responder(await viaticos.EjecutarAsync(IdUsuarioActual, idInforme, ct));

    /// <summary>HU-59 Pestaña Historial. Query: categoria (todos · edicion · precotizacion · revision · sistema).</summary>
    [RequierePermiso("rt_bandeja", "precot_ver")]
    [HttpGet("{idInforme:long}/historial")]
    public async Task<IActionResult> Historial(long idInforme, [FromQuery] string? categoria, CancellationToken ct = default)
        => Responder(await historial.EjecutarAsync(idInforme, categoria, IdUsuarioActual, ct));
}
