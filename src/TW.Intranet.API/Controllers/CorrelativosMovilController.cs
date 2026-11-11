using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-14 (Técnico: solicitud de correlativo, mis tickets y certificado) y HU-34 (Jefe de Metrología: correlativos, asignación y reserva diaria).</summary>
[ApiController]
[Authorize]
[Route("api/movil/correlativos")]
public class CorrelativosMovilController(
    CorrelativosTecnicoMovilCasoDeUso    tecnico,
    CorrelativosJefaturaMovilCasoDeUso   jefatura,
    ILogger<CorrelativosMovilController> logger) : ControladorAppMovil(logger)
{
    // ── Técnico (HU-14) ──────────────────────────────────────────────────────────────────

    /// <summary>
    /// Datos para pedir o usar el correlativo de un equipo: orden, equipo, serie, código, COD TW, clase y capacidad, OS / OM según la RQ, tipos de certificado, si se puede
    /// solicitar (y por qué no), el ticket abierto, el correlativo asignado sin usar y la reserva libre del técnico. Solo lectura.
    /// </summary>
    [HttpGet("servicios/{idOs:long}/equipos/{idOsEquipo:long}/solicitud")]
    public async Task<IActionResult> ObtenerSolicitud(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await tecnico.ObtenerSolicitudAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Solicita el correlativo a Metrología (crea el ticket TK-MET-##### y avisa al Jefe de Metrología). Exige los ensayos finalizados y el equipo en ejecución.</summary>
    [HttpPost("servicios/{idOs:long}/equipos/{idOsEquipo:long}/tickets")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> Solicitar(long idOs, long idOsEquipo, [FromBody] SolicitarCorrelativoDto? d, CancellationToken ct)
        => Responder(await tecnico.SolicitarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Guarda el N° de certificado del equipo (el correlativo asignado o uno de la reserva del técnico) en su informe técnico y marca el correlativo como usado.</summary>
    [HttpPut("servicios/{idOs:long}/equipos/{idOsEquipo:long}/certificado")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> GuardarCertificado(long idOs, long idOsEquipo, [FromBody] GuardarCertificadoDto? d, CancellationToken ct)
        => Responder(await tecnico.GuardarCertificadoAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>"Mis tickets": los del técnico que inició sesión. filtro = todos | pendientes | asignados (por defecto todos); idOs opcional.</summary>
    [HttpGet("tickets")]
    public async Task<IActionResult> ObtenerTickets([FromQuery] string? filtro, [FromQuery] long? idOs, CancellationToken ct)
        => Responder(await tecnico.ObtenerTicketsAsync(IdUsuarioActual, filtro, idOs, ct));

    /// <summary>Genera la reserva diaria de correlativos del propio técnico de Metrología (idempotente por día; a quien no es técnico de Metrología no le genera nada).</summary>
    [HttpPost("reserva")]
    public async Task<IActionResult> GenerarMiReserva(CancellationToken ct)
        => Responder(await tecnico.GenerarMiReservaAsync(IdUsuarioActual, ct));

    // ── Jefe de Metrología (HU-34) ───────────────────────────────────────────────────────

    /// <summary>Correlativos · solicitudes de los técnicos: KPIs, tickets pendientes y asignados hoy (con patrón y resultado), el siguiente correlativo sugerido y la reserva por técnico. Solo Metrología.</summary>
    [HttpGet("jefatura")]
    public async Task<IActionResult> ObtenerPanel(CancellationToken ct)
        => Responder(await jefatura.ObtenerPanelAsync(IdUsuarioActual, ct));

    /// <summary>Genera la reserva diaria de TODOS los técnicos de Metrología (la app la dispara al abrir la pantalla; idempotente por día).</summary>
    [HttpPost("jefatura/reserva")]
    public async Task<IActionResult> GenerarReserva(CancellationToken ct)
        => Responder(await jefatura.GenerarReservaAsync(IdUsuarioActual, ct));

    /// <summary>Asigna el correlativo a un ticket solicitado (vacío = el siguiente sugerido; editable con el formato CC-0000-AAAA) y avisa al técnico.</summary>
    [HttpPost("jefatura/tickets/{idTicket:long}/asignar")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> Asignar(long idTicket, [FromBody] AsignarCorrelativoDto? d, CancellationToken ct)
        => Responder(await jefatura.AsignarAsync(IdUsuarioActual, idTicket, d, ct));
}
