using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-32 — Alertas y apoyo en campo (Jefe de Área): el pedido de apoyo del técnico ante un error crítico (tabla del ensayo), con las decisiones
/// (llamar, pedir repetir el ensayo, indicar ajuste y nueva calibración), registrar / escalar una incidencia y reasignar el servicio a un técnico cercano.
/// El jefe sale del token y solo ve los servicios de su área.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/alertas")]
public class AlertasCampoMovilController(
    ObtenerAlertaCampoMovilCasoDeUso            obtener,
    AccionAlertaCampoMovilCasoDeUso             accion,
    ObtenerTecnicosReasignacionMovilCasoDeUso   tecnicos,
    ReasignarTecnicoMovilCasoDeUso              reasignar,
    RegistrarIncidenciaCampoMovilCasoDeUso      incidencia,
    ILogger<AlertasCampoMovilController>        logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoPeticion = 6 * 1024 * 1024;

    /// <summary>Formulario multipart de la incidencia. La foto (JPEG de la cámara) es opcional.</summary>
    public class IncidenciaFormulario
    {
        public int     IdTipo      { get; set; }
        /// <summary>baja · media · alta · critica.</summary>
        public string? Severidad   { get; set; }
        /// <summary>retrasa · detiene.</summary>
        public string? Impacto     { get; set; }
        public string? Descripcion { get; set; }
        public bool    Escalar     { get; set; }
        public IFormFile? Foto     { get; set; }
    }

    /// <summary>La alerta (aviso «Ensayo con error crítico»): quién pidió apoyo, la OS, el equipo y la tabla del ensayo.</summary>
    [HttpGet("{idNotificacion:long}")]
    public async Task<IActionResult> Obtener(long idNotificacion, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idNotificacion, ct));

    /// <summary>Decisión del jefe: <c>llamar</c> (registra la llamada y devuelve el teléfono), <c>repetir</c> o <c>ajuste</c> (avisan al técnico).</summary>
    [HttpPost("{idNotificacion:long}/acciones")]
    public async Task<IActionResult> Accion(long idNotificacion, [FromBody] AccionAlertaSolicitud cuerpo, CancellationToken ct)
        => Responder(await accion.EjecutarAsync(IdUsuarioActual, idNotificacion, cuerpo?.Accion, cuerpo?.Mensaje, ct));

    /// <summary>Técnicos cercanos de la misma especialidad y con SSOMA conforme a los que se puede reasignar el servicio.</summary>
    [HttpGet("servicios/{idOs:long}/tecnicos")]
    public async Task<IActionResult> Tecnicos(long idOs, CancellationToken ct)
        => Responder(await tecnicos.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Reasigna el servicio al técnico indicado (avisa al anterior y al nuevo).</summary>
    [HttpPost("servicios/{idOs:long}/reasignar")]
    public async Task<IActionResult> Reasignar(long idOs, [FromBody] ReasignarSolicitud cuerpo, CancellationToken ct)
        => Responder(await reasignar.EjecutarAsync(IdUsuarioActual, idOs, cuerpo?.IdTecnico ?? 0, ct));

    /// <summary>Registra una incidencia del servicio (tipo, severidad, impacto, descripción y foto) y, con <c>escalar</c>, la escala y avisa a Operaciones.</summary>
    [HttpPost("servicios/{idOs:long}/incidencias")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Incidencia(long idOs, [FromForm] IncidenciaFormulario f, CancellationToken ct)
    {
        await using var contenido = f.Foto?.OpenReadStream();
        return Responder(await incidencia.EjecutarAsync(
            IdUsuarioActual, idOs, f.IdTipo, f.Severidad, f.Impacto, f.Descripcion, f.Escalar, contenido, f.Foto?.Length ?? 0, ct));
    }
}
