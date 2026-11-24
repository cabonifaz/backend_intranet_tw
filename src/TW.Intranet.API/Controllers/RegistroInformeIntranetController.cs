using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// HU-55 — Registrar el informe de un equipo desde la intranet (Asistente de Seguimiento o Jefe de Operaciones) cuando el técnico no puede usar la app móvil (por ejemplo, la planta
/// no permite celulares). El flujo es el mismo del móvil (variables ambientales, evidencias, ensayos, cabecera, correlativo, cierre y generar informe) en rutas aparte.
/// El informe queda a nombre del TÉCNICO asignado; se guarda quién lo registró. Sin GPS ni hora de captura del teléfono. Todas las acciones exigen seg_registrar_informe y cada SP
/// vuelve a validarlo. Un equipo lo registra una sola persona a la vez: si otra lo tiene abierto responde 409.
/// </summary>
[ApiController]
[Authorize]
[Route("api/intranet/servicios/{idOs:long}")]
public class RegistroInformeIntranetController(
    ContextoRegistroIntranetCasoDeUso      contexto,
    SesionRegistroIntranetCasoDeUso        sesion,
    InformeEnCursoIntranetCasoDeUso        informeEnCurso,
    TrabajoRegistroIntranetCasoDeUso       trabajo,
    EvidenciasRegistroIntranetCasoDeUso    evidencias,
    EnsayosRegistroIntranetCasoDeUso       ensayos,
    CabeceraRegistroIntranetCasoDeUso      cabecera,
    CorrelativoRegistroIntranetCasoDeUso   correlativo,
    CierreRegistroIntranetCasoDeUso        cierre,
    FirmaConstanciaRegistroIntranetCasoDeUso firmaConstancia,
    ILogger<RegistroInformeIntranetController> logger) : ControladorAppMovil(logger)
{
    private const string Accion = "seg_registrar_informe";
    private const long TamanoMaximoEvidencia = 24 * 1024 * 1024;
    private const long TamanoMaximoFoto = 8 * 1024 * 1024;

    /// <summary>Formulario multipart de una captura de evidencia. Sin GPS ni hora de captura: lo hace una persona desde la intranet.</summary>
    public class CapturaEvidenciaIntranetFormulario
    {
        public string?    Codigo      { get; set; }
        public int?       Pagina      { get; set; }
        public string?    DuracionSeg { get; set; }
        /// <summary>Contenido leído del QR (solo evidencia "qr").</summary>
        public string?    QrTexto     { get; set; }
        /// <summary>Foto JPEG, o el video MP4 del encendido.</summary>
        public IFormFile? Archivo     { get; set; }
        /// <summary>Cuadro JPEG del video (lo analiza la IA y sirve de miniatura).</summary>
        public IFormFile? Cuadro      { get; set; }
    }

    /// <summary>Foto de una falla (JPEG). Devuelve su id para enviarlo en "fotos" de la falla al guardar la cabecera.</summary>
    public class FotoFallaIntranetFormulario
    {
        public IFormFile? Archivo { get; set; }
    }

    /// <summary>Formulario multipart del formato físico (foto del papel firmado y nombre de quien firmó).</summary>
    public class FormatoFisicoIntranetFormulario
    {
        public string?    Nombre { get; set; }
        public IFormFile? Foto   { get; set; }
    }

    /// <summary>2 → 200, 1 → 400 (o 409 si otra persona tiene el equipo abierto), 3 → 500 con mensaje genérico. Datos de operación: sin caché.</summary>
    private IActionResult Resp<T>(RespuestaDto<T> r)
    {
        Response.Headers["Cache-Control"] = "no-store";
        return r.IdTipoMensaje == 1 && ReglasRegistroIntranet.EsConflicto(r.Mensaje)
            ? StatusCode(StatusCodes.Status409Conflict, new RespuestaDto<T>(1, ReglasRegistroIntranet.QuitarPrefijo(r.Mensaje)))
            : Responder(r);
    }

    // ── 1. Lectura ───────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Para arrancar el asistente de registro, en una sola llamada: OS, cliente y planta, equipo, técnico asignado, informeFisico, el estado de cada etapa, si el equipo ya está iniciado
    /// y quién lo tiene abierto, y los catálogos. SOLO LECTURA: no marca llegada, no inicia el equipo y no toma el bloqueo.
    /// </summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/contexto-registro")]
    public async Task<IActionResult> ContextoRegistro(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await contexto.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Lo ya cargado del equipo (trabajo, evidencias, ensayos y cabecera) para retomar el registro. Una parte que aún no se puede leer viene nula y se explica en avisos.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/informe-en-curso")]
    public async Task<IActionResult> InformeEnCurso(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await informeEnCurso.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    // ── 2. Sesión de registro ────────────────────────────────────────────────────────────────

    /// <summary>
    /// "Comenzar registro": marca la llegada y el inicio del equipo con la hora indicada, y toma el bloqueo (409 si otra persona ya lo tiene). Idempotente. Cuerpo: inicio y fin (hora de Lima),
    /// motivo (código de MOTIVO_CAMBIO_MANUAL) y comentario opcional. Estados de OS permitidos: programada, reprogramada, en_ruta, en_ejecucion y pausada.
    /// </summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/iniciar-registro")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> IniciarRegistro(long idOs, long idOsEquipo, [FromBody] PeticionIniciarRegistroIntranetDto? d, CancellationToken ct)
        => Resp(await sesion.IniciarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Libera el bloqueo del equipo (al salir del asistente). Generar el informe también lo libera.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/liberar-registro")]
    public async Task<IActionResult> LiberarRegistro(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await sesion.LiberarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Pausa el OTRO equipo que el técnico dejó en ejecución (un técnico solo trabaja en un equipo a la vez), para poder iniciar este.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/pausar-equipo-abierto")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> PausarEquipoAbierto(long idOs, long idOsEquipo, [FromBody] PeticionPausarEquipoAbiertoIntranetDto? d, CancellationToken ct)
        => Resp(await sesion.PausarEquipoAbiertoAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    // ── 3. Variables ambientales, evidencias, ensayos y cabecera ─────────────────────────────

    /// <summary>Temperatura (°C) y humedad (%) obligatorias; procedencia opcional ("N.I" por defecto). Fecha y hora las pone el servidor. Devuelve el trabajo actualizado.</summary>
    [RequierePermiso(Accion)]
    [HttpPut("equipos/{idOsEquipo:long}/variables-ambientales")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> VariablesAmbientales(long idOs, long idOsEquipo, [FromBody] PeticionVariablesAmbientalesMovilDto? d, CancellationToken ct)
        => Resp(await trabajo.GuardarVariablesAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Panel de las evidencias (9, u 8 si el servicio no lleva informe físico) con su estado, el avance y las fotos adicionales.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/evidencias")]
    public async Task<IActionResult> Evidencias(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await evidencias.ObtenerAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Sube una evidencia (foto JPEG, microvideo MP4 de 3 a 5 s para el encendido, o el texto del QR). La IA la valida igual que en el móvil; una toma rechazada se conserva para poder forzarla.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/evidencias")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoEvidencia)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoEvidencia)]
    public async Task<IActionResult> SubirEvidencia(long idOs, long idOsEquipo, [FromForm] CapturaEvidenciaIntranetFormulario f, CancellationToken ct)
    {
        var dto = new CapturaEvidenciaMovilDto(f.Codigo, f.Pagina ?? 1, null, null, null, null, Decimal(f.DuracionSeg), f.QrTexto);
        await using var a = f.Archivo?.OpenReadStream();
        await using var c = f.Cuadro?.OpenReadStream();
        return Resp(await evidencias.RegistrarAsync(IdUsuarioActual, idOs, idOsEquipo, dto, a, f.Archivo?.Length ?? 0, c, f.Cuadro?.Length ?? 0, ct));
    }

    /// <summary>Acepta a la fuerza una foto rechazada por la IA, solo con un motivo (3 a 300 caracteres). Queda como excepción visible para Jefatura y NO cuenta contra el técnico. Devuelve el panel.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/evidencias/{idEvidencia:long}/forzar")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> ForzarEvidencia(long idOs, long idOsEquipo, long idEvidencia, [FromBody] PeticionForzarEvidenciaMovilDto? d, CancellationToken ct)
        => Resp(await evidencias.ForzarAsync(IdUsuarioActual, idOs, idOsEquipo, idEvidencia, d, ct));

    /// <summary>Quita una foto ADICIONAL (las 9 del panel no se quitan). Devuelve el panel actualizado.</summary>
    [RequierePermiso(Accion)]
    [HttpDelete("equipos/{idOsEquipo:long}/evidencias/adicionales/{idEvidencia:long}")]
    public async Task<IActionResult> QuitarEvidenciaAdicional(long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct)
        => Resp(await evidencias.QuitarAdicionalAsync(IdUsuarioActual, idOs, idOsEquipo, idEvidencia, ct));

    /// <summary>El archivo de una evidencia (foto, video o, con ?cuadro=true, el cuadro del video).</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/evidencias/{idEvidencia:long}/archivo")]
    public async Task<IActionResult> ArchivoEvidencia(long idOs, long idOsEquipo, long idEvidencia, [FromQuery] bool cuadro, CancellationToken ct)
    {
        var (contenido, tipo, mensaje) = await evidencias.ArchivoAsync(IdUsuarioActual, idOs, idOsEquipo, idEvidencia, cuadro, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Evidencia no encontrada.")) : File(contenido, tipo!, enableRangeProcessing: true);
    }

    /// <summary>Ensayos de pesaje y excentricidad guardados, con error, EMP y conformidad calculados por el servidor.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/ensayos")]
    public async Task<IActionResult> Ensayos(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await ensayos.ObtenerAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Guarda (o finaliza) los ensayos: solo se envían carga e indicación; error, EMP y resultado los calcula el servidor. Devuelve los ensayos actualizados.</summary>
    [RequierePermiso(Accion)]
    [HttpPut("equipos/{idOsEquipo:long}/ensayos")]
    [RequestSizeLimit(64 * 1024)]
    public async Task<IActionResult> GuardarEnsayos(long idOs, long idOsEquipo, [FromBody] GuardarEnsayosMovilDto? d, CancellationToken ct)
        => Resp(await ensayos.GuardarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Las 3 pestañas de la cabecera del informe (Datos · Detalle Serv. · Observación y pruebas) y los catálogos de opciones.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/cabecera-informe")]
    public async Task<IActionResult> CabeceraInforme(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await cabecera.ObtenerAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Guarda las secciones que vienen de la cabecera (una sección ausente no se toca). Devuelve la cabecera actualizada.</summary>
    [RequierePermiso(Accion)]
    [HttpPut("equipos/{idOsEquipo:long}/cabecera-informe")]
    [RequestSizeLimit(64 * 1024)]
    public async Task<IActionResult> GuardarCabeceraInforme(long idOs, long idOsEquipo, [FromBody] GuardarCabeceraInformeMovilDto? d, CancellationToken ct)
        => Resp(await cabecera.GuardarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Foto de una falla (JPEG). Devuelve su id: se envía en "fotos" de la falla al guardar la cabecera.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/cabecera-informe/fotos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoFoto)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoFoto)]
    public async Task<IActionResult> SubirFotoFalla(long idOs, long idOsEquipo, [FromForm] FotoFallaIntranetFormulario f, CancellationToken ct)
    {
        await using var a = f.Archivo?.OpenReadStream();
        return Resp(await cabecera.SubirFotoFallaAsync(IdUsuarioActual, idOs, idOsEquipo, a, f.Archivo?.Length ?? 0, ct));
    }

    // ── 4. Correlativo y certificado (etapa 5) ───────────────────────────────────────────────

    /// <summary>Datos para pedir o usar el correlativo: tipos de certificado, el ticket abierto y el correlativo asignado sin usar. Solo lectura.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/correlativo")]
    public async Task<IActionResult> Correlativo(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await correlativo.ObtenerSolicitudAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Solicita el correlativo a Metrología. El ticket queda a nombre del TÉCNICO; Metrología lo asigna aparte.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/correlativo/solicitar")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> SolicitarCorrelativo(long idOs, long idOsEquipo, [FromBody] SolicitarCorrelativoDto? d, CancellationToken ct)
        => Resp(await correlativo.SolicitarAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    /// <summary>Guarda el N° de certificado (el correlativo que asignó Metrología) en el informe del equipo.</summary>
    [RequierePermiso(Accion)]
    [HttpPut("equipos/{idOsEquipo:long}/correlativo/certificado")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> GuardarCertificado(long idOs, long idOsEquipo, [FromBody] GuardarCertificadoDto? d, CancellationToken ct)
        => Resp(await correlativo.GuardarCertificadoAsync(IdUsuarioActual, idOs, idOsEquipo, d, ct));

    // ── 5. Cierre y generar el informe ───────────────────────────────────────────────────────

    /// <summary>Hard Stop: valida las 5 etapas y devuelve la validación completa o los pendientes por etapa. No escribe nada.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("equipos/{idOsEquipo:long}/cierre")]
    public async Task<IActionResult> Cierre(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await cierre.ValidarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Con las 5 etapas conformes genera el informe (N° NNNN-AAAA) a nombre del técnico, deja el equipo completado y libera el bloqueo. Quedan guardados quién lo registró y la vía.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("equipos/{idOsEquipo:long}/informe")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> GenerarInforme(long idOs, long idOsEquipo, CancellationToken ct)
        => Resp(await cierre.GenerarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    // ── 6. Firma de informes y constancia (a nivel de la OS): solo formato físico y cliente ausente ──

    /// <summary>Informes de la OS con sus responsables, el plazo de aceptación tácita y el avance de firmas.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("firma-informes")]
    public async Task<IActionResult> FirmaInformes(long idOs, CancellationToken ct)
        => Resp(await firmaConstancia.FirmasAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Firma de un responsable en formato físico: foto del papel firmado y nombre de quien firmó.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("firma-informes/{clave}/fisico")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoFoto)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoFoto)]
    public async Task<IActionResult> FirmarInformeFisico(long idOs, string clave, [FromForm] FormatoFisicoIntranetFormulario f, CancellationToken ct)
    {
        await using var s = f.Foto?.OpenReadStream();
        return Resp(await firmaConstancia.FirmarFisicoAsync(IdUsuarioActual, idOs, clave, s, f.Foto?.Length ?? 0, f.Nombre, ct));
    }

    /// <summary>"Cliente ausente" de un responsable, con el motivo (de 5 a 300 caracteres).</summary>
    [RequierePermiso(Accion)]
    [HttpPost("firma-informes/{clave}/ausente")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> FirmarInformeAusente(long idOs, string clave, [FromBody] PeticionFirmaAusenteIntranetDto? d, CancellationToken ct)
        => Resp(await firmaConstancia.FirmarAusenteAsync(IdUsuarioActual, idOs, clave, d, ct));

    /// <summary>Datos de la constancia: cliente, contacto, equipos intervenidos, firma del cliente, envío y responsables que faltan firmar.</summary>
    [RequierePermiso(Accion)]
    [HttpGet("constancia")]
    public async Task<IActionResult> Constancia(long idOs, CancellationToken ct)
        => Resp(await firmaConstancia.ConstanciaAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Formato físico de la constancia: foto del papel firmado y nombre de quien firmó. Devuelve la constancia actualizada.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("constancia/fisico")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoFoto)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoFoto)]
    public async Task<IActionResult> ConstanciaFisico(long idOs, [FromForm] FormatoFisicoIntranetFormulario f, CancellationToken ct)
    {
        await using var s = f.Foto?.OpenReadStream();
        return Resp(await firmaConstancia.ConstanciaFisicoAsync(IdUsuarioActual, idOs, s, f.Foto?.Length ?? 0, f.Nombre, ct));
    }

    /// <summary>"Generar constancia": exige la firma del cliente (formato físico). Si todo está firmado cierra el servicio.</summary>
    [RequierePermiso(Accion)]
    [HttpPost("constancia/generar")]
    public async Task<IActionResult> ConstanciaGenerar(long idOs, CancellationToken ct)
        => Resp(await firmaConstancia.ConstanciaGenerarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>El PDF de la constancia ya generada (o, con ?tipo=foto, la foto del formato físico).</summary>
    [RequierePermiso(Accion)]
    [HttpGet("constancia/archivo")]
    public async Task<IActionResult> ConstanciaArchivo(long idOs, [FromQuery] string? tipo, CancellationToken ct)
    {
        var (contenido, mime, mensaje) = await firmaConstancia.ConstanciaArchivoAsync(IdUsuarioActual, idOs, tipo, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Archivo no encontrado.")) : File(contenido, mime!);
    }

    private static decimal? Decimal(string? texto) =>
        decimal.TryParse(texto, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : null;
}
