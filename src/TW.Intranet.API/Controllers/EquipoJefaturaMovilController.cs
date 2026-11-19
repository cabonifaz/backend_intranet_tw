using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-36 — Mi equipo (Jefe de Área): asistencia y ubicación de los técnicos de hoy según el Reloj marcador (en labores, refrigerio, tardanza, sin marcar), la ficha de cada técnico
/// (SSOMA, marcaciones del día, carga de la semana, teléfono) y sus horas contabilizadas (calendario por día «desde que inicia el servicio hasta que finaliza», acumulado semanal y mensual e historial
/// guardado de cada mes). Alcance Área + Rol de la app: Gerencia, Operaciones, Administración, TI, SSOMA, Calidad y Comercial (cualquier rol) y Administradores ven a todos los técnicos; el Supervisor de
/// Servicio Técnico / Metrología, solo a los de su área. El id del jefe sale del token; un técnico fuera de su equipo responde con un mensaje de negocio.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura/equipo")]
public class EquipoJefaturaMovilController(
    ObtenerEquipoJefaturaMovilCasoDeUso       obtener,
    ObtenerFichaEquipoTecnicoMovilCasoDeUso   obtenerFicha,
    ObtenerHorasTecnicoMovilCasoDeUso         obtenerHoras,
    ILogger<EquipoJefaturaMovilController>    logger) : ControladorAppMovil(logger)
{
    /// <summary>«Mi equipo»: KPIs (en labores, refrigerio, tardanza, sin marcar) y los técnicos de hoy con su servicio actual y su ubicación.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Ficha de un técnico: cargo, área, teléfono (para llamar), SSOMA, marcaciones del día y carga de la semana.</summary>
    [HttpGet("tecnicos/{idTecnico:long}")]
    public async Task<IActionResult> ObtenerFicha(long idTecnico, CancellationToken ct)
        => Responder(await obtenerFicha.EjecutarAsync(IdUsuarioActual, idTecnico, ct));

    /// <summary>
    /// «Ver las horas contabilizadas»: el calendario del mes (horas por día), el acumulado por semana, el total del mes y el historial de meses guardados. ?mes=AAAA-MM (por defecto el mes actual de Lima;
    /// no futuro ni de hace más de 24 meses).
    /// </summary>
    [HttpGet("tecnicos/{idTecnico:long}/horas")]
    public async Task<IActionResult> ObtenerHoras(long idTecnico, [FromQuery] string? mes, CancellationToken ct)
        => Responder(await obtenerHoras.EjecutarAsync(IdUsuarioActual, idTecnico, mes, ct));
}
