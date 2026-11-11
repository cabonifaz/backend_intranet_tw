using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-19 — Asistente IA y Procedimientos: consultas por texto, voz o sugerencias sobre el equipo en trabajo, respondidas SOLO con los manuales y procedimientos
/// oficiales del equipo (advertencia de seguridad, pasos y fuente con sección y página), con "Ver fuente", valoración y "Guardados" para leer sin conexión.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/asistente")]
public class AsistenteMovilController(
    ObtenerInicioAsistenteMovilCasoDeUso     inicio,
    ObtenerEquiposAsistenteMovilCasoDeUso    equipos,
    ConsultarAsistenteMovilCasoDeUso         consultar,
    ObtenerConsultaAsistenteMovilCasoDeUso   consulta,
    ValorarConsultaAsistenteMovilCasoDeUso   valorar,
    ObtenerFuenteAsistenteMovilCasoDeUso     fuente,
    TranscribirVozAsistenteMovilCasoDeUso    voz,
    ListarGuardadosAsistenteMovilCasoDeUso   listarGuardados,
    GuardarAsistenteMovilCasoDeUso           guardar,
    ObtenerGuardadoAsistenteMovilCasoDeUso   obtenerGuardado,
    EliminarGuardadoAsistenteMovilCasoDeUso  eliminarGuardado,
    ILogger<AsistenteMovilController>        logger) : ControladorAppMovil(logger)
{
    /// <summary>Margen sobre el tope del audio para el formulario multipart (cabeceras y límites).</summary>
    private const long TamanoMaximoPeticionVoz = EntradaAsistenteMovil.MaxBytesAudio + 512 * 1024;

    /// <summary>Formulario multipart de la consulta por voz.</summary>
    public class VozFormulario
    {
        /// <summary>Audio grabado en la app (m4a/mp4, aac, mp3, wav…), de hasta 5 MB.</summary>
        public IFormFile? Audio { get; set; }
    }

    /// <summary>
    /// Inicio: el equipo en contexto, los documentos oficiales que consultará el asistente, las sugerencias y las consultas recientes. Sin parámetros usa el equipo en
    /// ejecución del técnico (contexto null si no hay uno); con idOs e idOsEquipo, ese equipo.
    /// </summary>
    [HttpGet("inicio")]
    public async Task<IActionResult> Inicio([FromQuery] long? idOs, [FromQuery] long? idOsEquipo, CancellationToken ct)
        => Responder(await inicio.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Los equipos de las OS activas del técnico para "Cambiar" el contexto, con cuántos documentos oficiales consultables tiene cada uno.</summary>
    [HttpGet("equipos")]
    public async Task<IActionResult> Equipos(CancellationToken ct)
        => Responder(await equipos.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>
    /// Consulta al asistente (texto, voz transcrita o sugerencia). Responde con los documentos oficiales del equipo, cita sección y página y comprueba el fragmento
    /// contra el PDF. Límite: 10 consultas por minuto y 200 por día por técnico.
    /// </summary>
    [HttpPost("consultas")]
    [RequestSizeLimit(4 * 1024)]
    public async Task<IActionResult> Consultar([FromBody] PeticionConsultaAsistenteMovilDto? d, CancellationToken ct)
        => Responder(await consultar.EjecutarAsync(IdUsuarioActual, d, ct));

    /// <summary>Reabre una consulta reciente con su respuesta. Solo del propio técnico.</summary>
    [HttpGet("consultas/{idConsulta:long}")]
    public async Task<IActionResult> Consulta(long idConsulta, CancellationToken ct)
        => Responder(await consulta.EjecutarAsync(IdUsuarioActual, idConsulta, ct));

    /// <summary>"¿Te sirvió la respuesta?": valoración (true/false) de la consulta.</summary>
    [HttpPost("consultas/{idConsulta:long}/valoracion")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> Valorar(long idConsulta, [FromBody] PeticionValoracionAsistenteMovilDto? d, CancellationToken ct)
        => Responder(await valorar.EjecutarAsync(IdUsuarioActual, idConsulta, d, ct));

    /// <summary>"Fuente consultada": el documento oficial, su sección y el fragmento que usó el asistente.</summary>
    [HttpGet("consultas/{idConsulta:long}/fuentes/{n:int}")]
    public async Task<IActionResult> Fuente(long idConsulta, int n, CancellationToken ct)
        => Responder(await fuente.EjecutarAsync(IdUsuarioActual, idConsulta, n, ct));

    /// <summary>Transcribe el audio de una consulta por voz (español). El audio no se guarda.</summary>
    [HttpPost("voz")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticionVoz)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticionVoz)]
    public async Task<IActionResult> Voz([FromForm] VozFormulario f, CancellationToken ct)
    {
        var a = f.Audio;
        if (a is null || a.Length <= 0) return Responder(new RespuestaDto<TranscripcionVozAsistenteMovilDto>(1, "Falta el audio de la consulta."));
        if (a.Length > EntradaAsistenteMovil.MaxBytesAudio)
            return Responder(new RespuestaDto<TranscripcionVozAsistenteMovilDto>(1, $"El audio no puede superar los {EntradaAsistenteMovil.MaxBytesAudio / 1024 / 1024} MB."));
        var declarado = (a.ContentType ?? string.Empty).Trim().ToLowerInvariant();
        if (!declarado.StartsWith("audio/") && declarado != "application/octet-stream" && declarado != "video/mp4")
            return Responder(new RespuestaDto<TranscripcionVozAsistenteMovilDto>(1, "El audio no es válido. Graba de nuevo tu consulta."));

        await using var s = a.OpenReadStream();
        using var m = new MemoryStream();
        await s.CopyToAsync(m, ct);
        return Responder(await voz.EjecutarAsync(IdUsuarioActual, m.ToArray(), ct));
    }

    /// <summary>"Guardados": respuestas y fragmentos guardados por el técnico, con buscador.</summary>
    [HttpGet("guardados")]
    public async Task<IActionResult> Guardados([FromQuery] string? busqueda, CancellationToken ct)
        => Responder(await listarGuardados.EjecutarAsync(IdUsuarioActual, busqueda, ct));

    /// <summary>"Guardar offline" (respuesta) o "Fragmento" (la sección citada): guarda una copia que la app lee sin conexión. Idempotente.</summary>
    [HttpPost("guardados")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Guardar([FromBody] PeticionGuardarAsistenteMovilDto? d, CancellationToken ct)
        => Responder(await guardar.EjecutarAsync(IdUsuarioActual, d, ct));

    /// <summary>Un guardado con su contenido completo.</summary>
    [HttpGet("guardados/{idGuardado:long}")]
    public async Task<IActionResult> Guardado(long idGuardado, CancellationToken ct)
        => Responder(await obtenerGuardado.EjecutarAsync(IdUsuarioActual, idGuardado, ct));

    /// <summary>Quita un guardado (eliminación lógica con auditoría).</summary>
    [HttpDelete("guardados/{idGuardado:long}")]
    public async Task<IActionResult> EliminarGuardado(long idGuardado, CancellationToken ct)
        => Responder(await eliminarGuardado.EjecutarAsync(IdUsuarioActual, idGuardado, ct));
}
