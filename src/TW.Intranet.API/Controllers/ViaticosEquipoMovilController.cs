using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-35 — Viáticos y gastos del equipo del Jefe de Área: resumen por servicio (asignado, rendido, por revisar), detalle con las líneas por técnico y los gastos rendidos, y la asignación
/// de viáticos por concepto (con la opción de dejarlos depositados). Mismas reglas que la intranet (HU-45: prog_bandeja para ver, prog_aprobar_reprogramacion para asignar y revisar) con el
/// alcance de la app: Gerencia, Operaciones, Administración, TI, SSOMA, Calidad y Comercial (cualquier rol) y Administradores ven todo; el Supervisor de Servicio Técnico / Metrología, solo su área.
/// La revisión de un gasto (aprobar, observar, rechazar) sigue en PUT api/movil/aprobaciones/gastos/{id}.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/jefatura/viaticos")]
public class ViaticosEquipoMovilController(
    ObtenerViaticosEquipoMovilCasoDeUso         obtener,
    ObtenerViaticoServicioEquipoMovilCasoDeUso  obtenerServicio,
    AsignarViaticoEquipoMovilCasoDeUso          asignar,
    ILogger<ViaticosEquipoMovilController>      logger) : ControladorAppMovil(logger)
{
    /// <summary>"Viáticos y gastos": KPIs (asignado, rendido, por revisar) y el resumen por servicio (máx. 50: rendición abierta o de los últimos 7 días).</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>Detalle de un servicio: técnicos con sus líneas de viáticos (por concepto, con su estado de depósito), gastos rendidos con la lectura de la IA y la versión para asignar.</summary>
    [HttpGet("{idOs:long}")]
    public async Task<IActionResult> ObtenerServicio(long idOs, CancellationToken ct)
        => Responder(await obtenerServicio.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>
    /// "Asignar viático": { idTecnico, movilidad, alimentacion, alojamiento, otros, depositado, version }. Un monto 0 o vacío quita esa línea si no está depositada; "depositado" deja los viáticos
    /// pendientes de ese técnico marcados como depositados. El técnico lo ve al instante en su app y recibe la notificación; Contabilidad recibe el aviso de lo pendiente de depósito.
    /// </summary>
    [HttpPut("{idOs:long}/asignacion")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> Asignar(long idOs, [FromBody] AsignarViaticoEquipoDto? dto, CancellationToken ct)
        => Responder(await asignar.EjecutarAsync(IdUsuarioActual, idOs, dto, ct));
}
