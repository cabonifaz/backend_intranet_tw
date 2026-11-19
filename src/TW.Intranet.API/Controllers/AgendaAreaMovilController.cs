using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-37 — Agenda y carga del área (Jefe de Área): la semana de los técnicos (matriz técnico × día con los servicios coloreados por estado), el día y la carga (horas y utilización), el banner
/// de conflictos de programación y su resolución rápida (cambiar de técnico con sugerencia, cambiar el horario o reprogramar con motivo). Envuelve la Programación de la intranet (HU-35 a HU-39: permisos
/// prog_bandeja para ver y prog_gestionar para resolver; el circuito directa / solicitud lo decide el servidor según el permiso del token) con el alcance Área + Rol de la app: Gerencia, Operaciones,
/// Administración, TI, SSOMA, Calidad y Comercial (cualquier rol) y Administradores ven a todos los técnicos; el Supervisor de Servicio Técnico / Metrología, solo a los de su área. La programación
/// completa sigue en la intranet (Módulo 8): aquí se consulta y se hacen ajustes rápidos.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura/agenda")]
public class AgendaAreaMovilController(
    ObtenerAgendaAreaMovilCasoDeUso        obtener,
    ObtenerConflictoAgendaMovilCasoDeUso   obtenerConflicto,
    ResolverConflictoAgendaMovilCasoDeUso  resolver,
    ILogger<AgendaAreaMovilController>     logger) : ControladorAppMovil(logger)
{
    /// <summary>
    /// La agenda de una semana: ?desde=yyyy-MM-dd (cualquier fecha de la semana; se normaliza al lunes; por defecto la semana actual de Lima; hasta 26 semanas antes o después). Trae los técnicos con sus
    /// días y servicios, los KPIs y los conflictos. Hasta = viernes, o domingo si hay servicios el fin de semana.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Obtener([FromQuery] string? desde, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, desde, ct));

    /// <summary>
    /// Modal «Conflicto de programación»: ?tipo=solapamiento|extension_duracion|baja|ssoma_vencido &amp;idTecnico= &amp;idOsA= &amp;idOsB= (solo en los cruces). Los servicios (con el que conviene mover),
    /// el técnico sugerido (libre, con SSOMA conforme y de tu alcance), el motivo sugerido y el catálogo de motivos.
    /// </summary>
    [HttpGet("conflictos/detalle")]
    public async Task<IActionResult> ObtenerConflicto([FromQuery] string? tipo, [FromQuery] long? idTecnico, [FromQuery] long? idOsA, [FromQuery] long? idOsB, CancellationToken ct)
        => Responder(await obtenerConflicto.EjecutarAsync(IdUsuarioActual, tipo, idTecnico, idOsA, idOsB, ct));

    /// <summary>
    /// Resuelve el conflicto: { tipo, idTecnico, idOsA, idOsB, opcion: reasignar | reprogramar, idOsObjetivo, idNuevoTecnico, fecha, horaInicio, horaFin, idMotivo, comentario }.
    /// Con prog_aprobar_reprogramacion el cambio se aplica al instante (modo «directa»); con solo prog_gestionar queda una solicitud pendiente (modo «solicitud»).
    /// </summary>
    [HttpPut("conflictos/resolver")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> Resolver([FromBody] ResolverConflictoAgendaDto? dto, CancellationToken ct)
        => Responder(await resolver.EjecutarAsync(IdUsuarioActual, dto, ct));
}
