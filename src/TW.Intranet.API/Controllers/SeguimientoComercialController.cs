using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TW.Intranet.API.Configuracion;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-17 Bandeja · HU-18 Detalle · HU-19 Registro · HU-20 Reprogramación · HU-21 Cierre del Seguimiento Comercial
/// (propuestas enviadas al cliente).
/// </summary>
[ApiController]
[Authorize]
public class SeguimientoComercialController(
    ObtenerBandejaSeguimientoCasoDeUso         obtenerBandeja,
    ObtenerDetalleSeguimientoCasoDeUso         obtenerDetalle,
    PrepararRegistroSeguimientoCasoDeUso       prepararRegistro,
    RegistrarSeguimientoCasoDeUso              registrarSeguimiento,
    RegistrarLlamadaSeguimientoCasoDeUso       registrarLlamada,
    GuardarBorradorCorreoSeguimientoCasoDeUso  guardarBorradorCorreo,
    EnviarCorreoSeguimientoCasoDeUso           enviarCorreo,
    SubirAdjuntosSeguimientoCasoDeUso          subirAdjuntos,
    ObtenerAdjuntoSeguimientoCasoDeUso         obtenerAdjunto,
    PrepararReprogramacionSeguimientoCasoDeUso prepararReprogramacion,
    ReprogramarAccionSeguimientoCasoDeUso      reprogramarAccion,
    PrepararCierreSeguimientoCasoDeUso         prepararCierre,
    RegistrarAceptacionSeguimientoCasoDeUso    registrarAceptacion,
    RegistrarRechazoSeguimientoCasoDeUso       registrarRechazo) : ControllerBase
{
    /// <summary>5 archivos de 10 MB + margen para el resto del multipart.</summary>
    private const long TamanoMaximoPeticion =
        SubirAdjuntosSeguimientoCasoDeUso.MaximoArchivos * SubirAdjuntosSeguimientoCasoDeUso.TamanoMaximoBytes + 1024 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r, bool noEncontradoComo404 = false) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => noEncontradoComo404 ? NotFound(r) : BadRequest(r),
            _ => StatusCode(500, r),
        };

    /// <summary>
    /// HU-17 — KPIs del pipeline, listado con días transcurridos, próxima acción y estado del SLA,
    /// y opciones del filtro de responsable (tal cual vienen de las propuestas en alcance).
    /// ?idResponsable=&amp;estado=&amp;busqueda=&amp;pagina=1&amp;porPagina=10
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_bandeja")]
    [HttpGet("api/crm/seguimiento")]
    public async Task<IActionResult> Bandeja([FromQuery] FiltrosBandejaSeguimientoDto filtros, CancellationToken ct = default)
        => Responder(await obtenerBandeja.EjecutarAsync(filtros, IdUsuarioActual, ct));

    /// <summary>
    /// HU-18 — Detalle del seguimiento de una propuesta: panel superior (monto, días, SLA restante),
    /// próxima acción, timeline de interacciones, próximas acciones, contactos, documentos
    /// y permisos de los botones (registrar seguimiento, aceptación y rechazo).
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_bandeja")]
    [HttpGet("api/crm/seguimiento/{idPropuesta:long}")]
    public async Task<IActionResult> Detalle(long idPropuesta, CancellationToken ct = default)
        => Responder(await obtenerDetalle.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));

    // ══════════════════════ HU-19 — Registro de acciones ══════════════════════

    /// <summary>
    /// HU-19 — Datos para los modales Registrar Seguimiento / Llamada / Correo: tipos de seguimiento,
    /// resultados, contactos, tipos de tarea, prioridades, responsables, plantillas (ya armadas)
    /// y el último borrador de correo del usuario.
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_registrar")]
    [HttpGet("api/crm/seguimiento/{idPropuesta:long}/registro/preparar")]
    public async Task<IActionResult> PrepararRegistro(long idPropuesta, CancellationToken ct = default)
        => Responder(await prepararRegistro.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));

    /// <summary>HU-19 — Registro general: tipo de seguimiento, resultado, notas y próxima acción opcional.</summary>
    [RequierePermiso("propuesta_seguimiento_registrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/registros")]
    public async Task<IActionResult> Registrar(long idPropuesta, [FromBody] RegistrarSeguimientoDto dto, CancellationToken ct = default)
        => Responder(await registrarSeguimiento.EjecutarAsync(idPropuesta, dto, IdUsuarioActual, ct));

    /// <summary>HU-19 — Registrar llamada: fecha y hora, duración, resultado, notas y próxima acción opcional.</summary>
    [RequierePermiso("propuesta_seguimiento_registrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/llamadas")]
    public async Task<IActionResult> RegistrarLlamada(long idPropuesta, [FromBody] RegistrarLlamadaDto dto, CancellationToken ct = default)
        => Responder(await registrarLlamada.EjecutarAsync(idPropuesta, dto, IdUsuarioActual, ct));

    /// <summary>HU-19 — Guardar borrador del correo (Para, CC, asunto, plantilla y cuerpo HTML).</summary>
    [RequierePermiso("propuesta_seguimiento_registrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/correos/borrador")]
    public async Task<IActionResult> GuardarBorradorCorreo(long idPropuesta, [FromBody] CorreoSeguimientoDto dto, CancellationToken ct = default)
        => Responder(await guardarBorradorCorreo.EjecutarAsync(idPropuesta, dto, IdUsuarioActual, ct));

    /// <summary>HU-19 — Enviar el correo y registrar el seguimiento (con próxima acción opcional).</summary>
    [RequierePermiso("propuesta_seguimiento_registrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/correos/enviar")]
    public async Task<IActionResult> EnviarCorreo(long idPropuesta, [FromBody] CorreoSeguimientoDto dto, CancellationToken ct = default)
        => Responder(await enviarCorreo.EjecutarAsync(idPropuesta, dto, IdUsuarioActual, ct));

    /// <summary>
    /// HU-19 — Documentos adjuntos de un seguimiento ya registrado (multipart/form-data, campo "archivos",
    /// hasta 5 archivos de 10 MB: PDF, imágenes, Word, Excel, .msg/.eml o .txt).
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_registrar")]
    [HttpPost("api/crm/seguimiento/registros/{idSeguimiento:long}/adjuntos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> SubirAdjuntos(long idSeguimiento, [FromForm] List<IFormFile>? archivos, CancellationToken ct = default)
    {
        var lista = (archivos ?? []).Where(a => a.Length > 0).ToList();
        if (lista.Count == 0)
            return BadRequest(new RespuestaDto<object>(1, "Seleccione al menos un archivo."));

        var streams = new List<Stream>();
        try
        {
            var entradas = new List<SubirAdjuntosSeguimientoCasoDeUso.ArchivoEntrada>();
            foreach (var a in lista)
            {
                var s = a.OpenReadStream();
                streams.Add(s);
                entradas.Add(new(s, a.FileName, a.Length));
            }
            return Responder(await subirAdjuntos.EjecutarAsync(idSeguimiento, entradas, IdUsuarioActual, ct));
        }
        finally
        {
            foreach (var s in streams) await s.DisposeAsync();
        }
    }

    /// <summary>HU-19 — Ver o descargar un adjunto de seguimiento.</summary>
    [RequierePermiso("propuesta_seguimiento_bandeja")]
    [HttpGet("api/crm/seguimiento/adjuntos/{idAdjunto:long}")]
    public async Task<IActionResult> ObtenerAdjunto(long idAdjunto, CancellationToken ct = default)
    {
        var r = await obtenerAdjunto.EjecutarAsync(idAdjunto, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return Responder(new RespuestaDto<object>(r.IdTipoMensaje, r.Mensaje), noEncontradoComo404: true);

        var disposicion = new ContentDispositionHeaderValue("inline");
        disposicion.SetHttpFileName(r.Datos.NombreArchivo);
        Response.Headers[HeaderNames.ContentDisposition] = disposicion.ToString();
        return File(r.Datos.Contenido, r.Datos.TipoContenido, enableRangeProcessing: true);
    }

    // ══════════════════════ HU-20 — Reprogramación de acciones ══════════════════════

    /// <summary>
    /// HU-20 — Datos del modal "Reprogramar Próxima Acción": acción actual (tipo, fecha, prioridad,
    /// responsable), tipos de acción, prioridades, responsables, motivos e historial de reprogramaciones.
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_reprogramar")]
    [HttpGet("api/crm/seguimiento/{idPropuesta:long}/reprogramacion/preparar")]
    public async Task<IActionResult> PrepararReprogramacion(long idPropuesta, CancellationToken ct = default)
        => Responder(await prepararReprogramacion.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));

    /// <summary>
    /// HU-20 — Reprogramar la próxima acción: { idTipoAccion, fecha, idPrioridad, idResponsable, idMotivo, detalle }.
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_reprogramar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/reprogramar")]
    public async Task<IActionResult> Reprogramar(long idPropuesta, [FromBody] ReprogramarAccionDto dto, CancellationToken ct = default)
        => Responder(await reprogramarAccion.EjecutarAsync(idPropuesta, dto, IdUsuarioActual, ct));

    // ══════════════════════ HU-21 — Cierre del seguimiento ══════════════════════

    /// <summary>
    /// HU-21 — Datos de los modales de cierre: cabecera (cliente, monto, RQ, responsable), tipos de aceptación,
    /// motivos de rechazo (tal cual) y contactos del cliente.
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_cerrar")]
    [HttpGet("api/crm/seguimiento/{idPropuesta:long}/cierre/preparar")]
    public async Task<IActionResult> PrepararCierre(long idPropuesta, CancellationToken ct = default)
        => Responder(await prepararCierre.EjecutarAsync(idPropuesta, IdUsuarioActual, ct));

    /// <summary>
    /// HU-21 — Registrar aceptación (JSON, flujo actual del front): { idTipoAceptacion, idContacto, fecha, comentario? }.
    /// La evidencia es obligatoria (observación 2026-10-15): el modal no deja guardar sin archivos y los sube
    /// enseguida con POST .../registros/{idSeguimiento}/adjuntos. La propuesta pasa a Órdenes de Compra.
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_cerrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/aceptar")]
    [Consumes("application/json")]
    public async Task<IActionResult> Aceptar(long idPropuesta, [FromBody] RegistrarAceptacionDto dto, CancellationToken ct = default)
        => Responder(await registrarAceptacion.EjecutarAsync(idPropuesta, dto, [], IdUsuarioActual, ct));

    /// <summary>
    /// HU-21 — Registrar aceptación con la evidencia en la misma petición (opcional, atómico):
    /// multipart/form-data con idTipoAceptacion, idContacto, fecha?, comentario? y "archivos" (1 a 5 archivos
    /// de 10 MB). El cierre y los adjuntos se registran juntos.
    /// </summary>
    [RequierePermiso("propuesta_seguimiento_cerrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/aceptar")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> AceptarConEvidencia(long idPropuesta, [FromForm] RegistrarAceptacionDto dto,
                                                         [FromForm] List<IFormFile>? archivos, CancellationToken ct = default)
    {
        var lista = (archivos ?? []).Where(a => a.Length > 0).ToList();
        if (lista.Count == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte al menos un archivo de evidencia de la aceptación."));

        var entrada = dto with { Fecha = dto.Fecha is { } f ? ZonaHorariaLima.AHoraLima(f) : null };
        var streams = new List<Stream>();
        try
        {
            var entradas = new List<SubirAdjuntosSeguimientoCasoDeUso.ArchivoEntrada>();
            foreach (var a in lista)
            {
                var s = a.OpenReadStream();
                streams.Add(s);
                entradas.Add(new(s, a.FileName, a.Length));
            }
            return Responder(await registrarAceptacion.EjecutarAsync(idPropuesta, entrada, entradas, IdUsuarioActual, ct));
        }
        finally
        {
            foreach (var s in streams) await s.DisposeAsync();
        }
    }

    /// <summary>HU-21 — Registrar rechazo: { idMotivo, fecha?, comentario (mín. 20) }. La propuesta queda rechazada.</summary>
    [RequierePermiso("propuesta_seguimiento_cerrar")]
    [HttpPost("api/crm/seguimiento/{idPropuesta:long}/rechazar")]
    public async Task<IActionResult> Rechazar(long idPropuesta, [FromBody] RegistrarRechazoDto dto, CancellationToken ct = default)
        => Responder(await registrarRechazo.EjecutarAsync(idPropuesta, dto, IdUsuarioActual, ct));
}
