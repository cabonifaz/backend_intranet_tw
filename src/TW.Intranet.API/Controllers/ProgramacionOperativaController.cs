using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-35 (Sprint 5) Bandeja de Programación Operativa, solo lectura: panorama de la semana, servicios pendientes de
/// acción de Operaciones y servicios ya programados. Cada fila trae las acciones que el usuario puede hacer: Programar
/// (HU-36), Reprogramar / Solicitar reprogramación (HU-38), Cancelar (POST api/crm/ordenes-servicio/{idOs}/anular) y
/// Ver detalle (GET api/crm/ordenes-servicio/{idOs}).
/// Acceso a la bandeja: prog_bandeja (módulo operaciones); el SP lo vuelve a validar.
/// HU-36: ficha "Programar Servicio", buscador de técnicos, validación previa, creación de la programación y derivación a
/// SSOMA. Acceso: prog_gestionar. Cada SP vuelve a validar el permiso.
/// </summary>
[ApiController]
[Route("api/operaciones/programacion")]
[Authorize]
public class ProgramacionOperativaController(
    ObtenerResumenProgramacionCasoDeUso         obtenerResumen,
    ObtenerPendientesProgramacionCasoDeUso      obtenerPendientes,
    ObtenerProgramadosProgramacionCasoDeUso     obtenerProgramados,
    ExportarPendientesProgramacionCasoDeUso     exportarPendientes,
    ExportarProgramadosProgramacionCasoDeUso    exportarProgramados,
    PrepararProgramacionCasoDeUso               prepararProgramacion,
    BuscarTecnicosProgramacionCasoDeUso         buscarTecnicos,
    CrearProgramacionCasoDeUso                  crearProgramacion,
    DerivarSsomaProgramacionCasoDeUso           derivarSsoma,
    ILogger<ProgramacionOperativaController>    logger) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>
    /// 2 → 200, 1 → 400 (regla de negocio o permiso). Desarrollo seguro: un error del sistema (3) no devuelve el mensaje
    /// técnico de la base de datos al cliente; el detalle solo va al log.
    /// </summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Programación operativa: error en {Ruta} (usuario {IdUsuario}): {Detalle}",
                Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo consultar la programación operativa. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>
    /// Tab Vista Principal: tarjetas, calendario de la semana, matriz de carga por técnico y alertas.
    /// ?fechaSemana=yyyy-MM-dd (cualquier día de la semana; vacío = la semana de hoy)
    /// &amp;busqueda= (opcional; acota solo el calendario por N° OS/OM, cliente, RUC o técnico)
    /// </summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet("resumen")]
    public async Task<IActionResult> Resumen([FromQuery] DateTime? fechaSemana, [FromQuery] string? busqueda, CancellationToken ct = default)
        => Responder(await obtenerResumen.EjecutarAsync(fechaSemana, busqueda, IdUsuarioActual, ct));

    /// <summary>
    /// Tab Pendientes: ?subEstado=todos|pendiente_programar|pendiente_conf_cliente|pendiente_reprogramacion|pendiente_ssoma
    /// &amp;tipo=OS|OM&amp;idCliente=&amp;idArea=&amp;idTecnico=&amp;idSede=&amp;zona=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// (trae además la cantidad por sub-estado con los demás filtros aplicados)
    /// </summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet("pendientes")]
    public async Task<IActionResult> Pendientes([FromQuery] FiltrosProgramacionDto filtros, CancellationToken ct = default)
        => Responder(await obtenerPendientes.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>Exportar XLSX de Pendientes con los mismos filtros (todas las filas, hasta 5000).</summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet("pendientes/exportar")]
    public async Task<IActionResult> ExportarPendientes([FromQuery] FiltrosProgramacionDto filtros, CancellationToken ct = default)
    {
        var r = await exportarPendientes.EjecutarAsync(filtros, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    /// <summary>
    /// Tab Programados: ?rango=todos|hoy|esta_semana|proxima_semana|personalizado&amp;fechaDesde=&amp;fechaHasta=
    /// &amp;tipo=OS|OM&amp;idCliente=&amp;idArea=&amp;idTecnico=&amp;idSede=&amp;zona=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// </summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet("programados")]
    public async Task<IActionResult> Programados([FromQuery] FiltrosProgramacionDto filtros, CancellationToken ct = default)
        => Responder(await obtenerProgramados.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>Exportar XLSX de Programados con los mismos filtros (todas las filas, hasta 5000).</summary>
    [RequierePermiso("prog_bandeja")]
    [HttpGet("programados/exportar")]
    public async Task<IActionResult> ExportarProgramados([FromQuery] FiltrosProgramacionDto filtros, CancellationToken ct = default)
    {
        var r = await exportarProgramados.EjecutarAsync(filtros, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }

    // ══════════════════════ HU-36 Programar una OS y asignar recursos ══════════════════════

    /// <summary>
    /// Ficha "Programar Servicio": datos heredados de la OS/OM (cliente, sede, propuesta, expediente), sus equipos y los
    /// requisitos SSOMA del cliente. Indica si la orden se puede programar (solo una EMITIDA sin programación activa).
    /// </summary>
    [RequierePermiso("prog_gestionar")]
    [HttpGet("ordenes/{idOs:long}/preparar")]
    public async Task<IActionResult> Preparar(long idOs, CancellationToken ct = default)
        => Responder(await prepararProgramacion.EjecutarAsync(idOs, IdUsuarioActual, ct));

    /// <summary>
    /// Buscador de técnicos y modal "Asignar Recurso": disponibilidad en el horario elegido, carga y cupo del día, SSOMA contra
    /// los requisitos del cliente/zona, experiencia con el cliente, scorecard y contadores por pestaña.
    /// ?fecha=yyyy-MM-dd&amp;horaInicio=HH:mm&amp;horaFin=HH:mm&amp;soloDisponibles=&amp;soloSsomaConforme=&amp;busqueda=&amp;sedeOperativa=
    /// &amp;tipoRecurso=tecnico|metrologo|externo
    /// </summary>
    [RequierePermiso("prog_gestionar")]
    [HttpGet("ordenes/{idOs:long}/tecnicos")]
    public async Task<IActionResult> Tecnicos(long idOs, [FromQuery] FiltrosTecnicosProgramacionDto filtros, CancellationToken ct = default)
        => Responder(await buscarTecnicos.EjecutarAsync(idOs, filtros, IdUsuarioActual, ct));

    /// <summary>
    /// Crea la programación activa de una OS emitida (cronograma, técnico principal, apoyo y equipos). Queda
    /// PENDIENTE DE CONFIRMACIÓN DEL CLIENTE y aparece en la bandeja. Las validaciones (SSOMA, solapamiento) bloquean con 400.
    /// </summary>
    [RequierePermiso("prog_gestionar")]
    [RequestSizeLimit(32 * 1024)]
    [HttpPost]
    public async Task<IActionResult> Crear([FromBody] CrearProgramacionDto dto, CancellationToken ct = default)
        => Responder(await crearProgramacion.EjecutarAsync(dto, IdUsuarioActual, ct));

    /// <summary>
    /// "Derivar al área SSOMA" desde el bloque de validación SSOMA: notifica a SSOMA qué técnicos no cumplen los requisitos
    /// del cliente/zona de la orden y qué les falta. No cambia la orden. Avisos repetidos (misma persona y orden en 10 min) → 400.
    /// </summary>
    [RequierePermiso("prog_gestionar")]
    [RequestSizeLimit(8 * 1024)]
    [HttpPost("ordenes/{idOs:long}/derivar-ssoma")]
    public async Task<IActionResult> DerivarSsoma(long idOs, [FromBody] DerivarSsomaDto dto, CancellationToken ct = default)
        => Responder(await derivarSsoma.EjecutarAsync(idOs, dto, IdUsuarioActual, ct));
}
