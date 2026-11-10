using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-28 — Menú de Jefatura único (jefes de área: Servicio Técnico, Metrología, Operaciones…; supervisores y administradores con área).</summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura")]
public class JefaturaMovilController(
    ObtenerMenuJefaturaMovilCasoDeUso            obtenerMenu,
    ObtenerPanelCampoMovilCasoDeUso              obtenerPanel,
    ObtenerServiciosJefaturaMovilCasoDeUso       obtenerServicios,
    ObtenerServicioJefaturaMovilCasoDeUso        obtenerServicio,
    ObtenerRutaServicioJefaturaMovilCasoDeUso    obtenerRuta,
    RegistrarSeguimientoJefaturaMovilCasoDeUso   registrarSeguimiento,
    ILogger<JefaturaMovilController>             logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// HU-29 — Panel de Campo en tiempo real: KPIs (en ruta, en ejecución, con demora, con incidencia, finalizados), un pin por técnico con el color de su estado y las
    /// alertas críticas primero. Servicios de HOY del alcance del jefe (área de la RQ para Servicio Técnico y Metrología; las demás áreas ven todo). Solo lectura.
    /// </summary>
    [HttpGet("panel-campo")]
    public async Task<IActionResult> ObtenerPanel(CancellationToken ct)
        => Responder(await obtenerPanel.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>
    /// HU-29 — "Servicios activos": lista con búsqueda (OS, cliente o técnico) y filtro (activos | demora | incidencias | finalizados; por defecto activos).
    /// Los chips con sus contadores salen sobre todo el alcance del jefe.
    /// </summary>
    [HttpGet("servicios")]
    public async Task<IActionResult> ObtenerServicios([FromQuery] string? filtro, [FromQuery] string? busqueda, CancellationToken ct)
        => Responder(await obtenerServicios.EjecutarAsync(IdUsuarioActual, filtro, busqueda, ct));

    /// <summary>HU-30 — Detalle del servicio: técnico, estado, hora programada, llegada, SLA, hitos del técnico y opciones del cambio de estado.</summary>
    [HttpGet("servicios/{idOs:long}")]
    public async Task<IActionResult> ObtenerServicio(long idOs, CancellationToken ct)
        => Responder(await obtenerServicio.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>HU-30 — Ubicación y ruta: última posición, recorrido GPS, velocidad, ETA, distancia, demora registrada por el técnico y eventos en ruta.</summary>
    [HttpGet("servicios/{idOs:long}/ruta")]
    public async Task<IActionResult> ObtenerRuta(long idOs, CancellationToken ct)
        => Responder(await obtenerRuta.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>
    /// HU-30 — Cambiar el estado operativo a mano (solo avanzar, con motivo y comentario). Queda en el historial del servicio con el usuario y la hora y avisa a Jefatura.
    /// Exige los permisos del seguimiento operativo (los valida el procedimiento).
    /// </summary>
    [HttpPost("servicios/{idOs:long}/estado")]
    [RequestSizeLimit(8 * 1024)]
    public async Task<IActionResult> CambiarEstado(long idOs, [FromBody] CambiarEstadoServicioDto? d, CancellationToken ct)
        => Responder(await registrarSeguimiento.CambiarEstadoAsync(IdUsuarioActual, idOs, d, ct));

    /// <summary>HU-30 — Deja constancia del aviso dado al cliente por el retraso (queda como nota del seguimiento). No envía correos ni mensajes al cliente.</summary>
    [HttpPost("servicios/{idOs:long}/aviso-cliente")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> AvisarCliente(long idOs, [FromBody] AvisarClienteDto? d, CancellationToken ct)
        => Responder(await registrarSeguimiento.AvisarClienteAsync(IdUsuarioActual, idOs, d, ct));

    /// <summary>
    /// Resumen del día para quien inició sesión (sale del token): programados, en ruta, en ejecución, con demora y aprobaciones
    /// pendientes. Metrología se filtra por el área según la RQ. Quien no tiene el menú de Jefatura recibe 400.
    /// </summary>
    [HttpGet("menu")]
    public async Task<IActionResult> ObtenerMenu(CancellationToken ct)
        => Responder(await obtenerMenu.EjecutarAsync(IdUsuarioActual, ct));
}
