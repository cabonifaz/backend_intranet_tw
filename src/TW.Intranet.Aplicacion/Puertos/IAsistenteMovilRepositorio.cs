using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>El equipo en contexto tal como lo necesita la IA: además de lo que ve la app, el tipo de equipo (descripción del suministro).</summary>
public record ContextoIaAsistente(
    long IdOs, string NumeroOs, long IdOsEquipo, string Nombre, int Numero, string? Marca, string? Modelo, string? CodigoCliente, string? NumeroSerie,
    string? ServicioSigla, string Estado, string? TipoEquipo);

/// <summary>
/// Un documento oficial del equipo (SP_ArmarDocumentosAsistenteMovil). Ubicacion = ruta interna del almacenamiento (procedimiento) o URL del manual del suministro.
/// Disponible = se puede intentar leer (el manual solo si es https).
/// </summary>
public record DocumentoAsistenteMovil(
    string IdDocumento, string Tipo, string Titulo, string? Version, string? Entidad, string? Actualizado, string Ubicacion, bool Disponible);

public record DocumentosAsistenteMovilDto(ContextoIaAsistente Contexto, List<DocumentoAsistenteMovil> Documentos);

/// <summary>La consulta recién registrada (fase 1) o completada (fase 2). CreadoEn en hora de Lima.</summary>
public record ConsultaRegistradaAsistente(long IdConsulta, DateTime? CreadoEn);

/// <summary>Una consulta guardada tal como está en la base: la respuesta va como JSON (CuerpoRespuestaAsistente). Null si no tiene respuesta.</summary>
public record ConsultaGuardadaAsistente(
    long IdConsulta, long IdOs, long IdOsEquipo, string Pregunta, string Origen, string Estado, DateTime? CreadoEn, string? RespuestaJson, bool? Util);

/// <summary>Un guardado tal como está en la base: el contenido va como JSON.</summary>
public record GuardadoCrudoAsistente(long IdGuardado, string Tipo, string Titulo, string? Subtitulo, DateTime? CreadoEn, int TamanoBytes, string? ContenidoJson);

/// <summary>Asistente IA y Procedimientos de la app móvil (App Mobile HU-19). Todo pasa por SP; el usuario siempre sale del token.</summary>
public interface IAsistenteMovilRepositorio
{
    Task<RespuestaDto<InicioAsistenteMovilDto>> ObtenerInicioAsync(long idUsuario, long? idOs, long? idOsEquipo, CancellationToken ct);

    Task<RespuestaDto<List<EquipoAsistenteMovilDto>>> ObtenerEquiposAsync(long idUsuario, CancellationToken ct);

    Task<RespuestaDto<DocumentosAsistenteMovilDto>> ObtenerDocumentosAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);

    /// <summary>Fase 1: valida, aplica el límite de uso (10 por minuto, 200 por día) y registra la consulta "procesando".</summary>
    Task<RespuestaDto<ConsultaRegistradaAsistente>> IniciarConsultaAsync(long idUsuario, long idOs, long idOsEquipo, string pregunta, string origen, CancellationToken ct);

    /// <summary>Fase 2: completa la consulta con su resultado (respondida | sin_respuesta | sin_fuentes | error_ia).</summary>
    Task<RespuestaDto<ConsultaRegistradaAsistente>> CompletarConsultaAsync(
        long idUsuario, long idConsulta, string estado, string? documentosJson, string? respuestaJson, string? motor, int duracionMs, CancellationToken ct);

    Task<RespuestaDto<ConsultaGuardadaAsistente>> ObtenerConsultaAsync(long idUsuario, long idConsulta, CancellationToken ct);

    Task<RespuestaDto<object>> ValorarConsultaAsync(long idUsuario, long idConsulta, bool util, CancellationToken ct);

    Task<RespuestaDto<List<GuardadoAsistenteMovilDto>>> ListarGuardadosAsync(long idUsuario, string? busqueda, CancellationToken ct);

    Task<RespuestaDto<GuardadoCrudoAsistente>> GuardarAsync(
        long idUsuario, long idConsulta, string tipo, int n, string titulo, string? subtitulo, string contenidoJson, CancellationToken ct);

    Task<RespuestaDto<GuardadoCrudoAsistente>> ObtenerGuardadoAsync(long idUsuario, long idGuardado, CancellationToken ct);

    Task<RespuestaDto<object>> EliminarGuardadoAsync(long idUsuario, long idGuardado, CancellationToken ct);
}

// ── IA y documentos ───────────────────────────────────────────────────────────────────────────────────────────

/// <summary>Un documento oficial ya leído que se le da a la IA. Numero = el "DOCUMENTO n" con el que la IA lo cita (empieza en 1).</summary>
public record DocumentoParaIa(int Numero, string IdDocumento, string Titulo, string Tipo, byte[] Pdf);

public record SolicitudAsistenteManuales(string Pregunta, ContextoIaAsistente Contexto, IReadOnlyList<DocumentoParaIa> Documentos);

/// <summary>Una cita de la IA: número del DOCUMENTO, sección y página como aparecen en él y el fragmento copiado textualmente.</summary>
public record CitaAsistenteIa(int Documento, string? Seccion, int? Pagina, string Fragmento);

/// <summary>Resultado de la IA: Error ≠ null = la IA no pudo responder (mensaje para el técnico). Encontrada = false = el tema no está en los documentos.</summary>
public record ResultadoAsistenteManuales(
    bool Encontrada, string? Advertencia, IReadOnlyList<string> Pasos, IReadOnlyList<CitaAsistenteIa> Citas, string? Motivo, string? Error);

/// <summary>Google Gemini: responde SOLO con los documentos oficiales dados y cita sección, página y fragmento; también transcribe el audio de la consulta por voz.</summary>
public interface IAsistenteManuales
{
    /// <summary>Hay API key de Gemini configurada.</summary>
    bool Disponible { get; }

    /// <summary>Modelo de IA que responde (para la bitácora).</summary>
    string Motor { get; }

    Task<ResultadoAsistenteManuales> ConsultarAsync(SolicitudAsistenteManuales solicitud, CancellationToken ct);

    /// <summary>Transcribe el audio (español). Texto null con Error = no se pudo.</summary>
    Task<(string? Texto, string? Error)> TranscribirAsync(byte[] audio, string tipoMime, CancellationToken ct);
}

/// <summary>Un documento oficial leído (Pdf) o la razón por la que no se pudo leer (Error).</summary>
public record DocumentoCargadoAsistente(DocumentoAsistenteMovil Documento, byte[]? Pdf, string? Error);

/// <summary>Resultado de comprobar una cita en el PDF: Verificada true / false / null (PDF sin texto). ContextoPosterior = lo que sigue al fragmento en la página.</summary>
public record VerificacionCitaAsistente(bool? Verificada, string? ContextoPosterior);

/// <summary>Lee los PDF oficiales (procedimientos del almacenamiento; manuales por https con guardas anti-SSRF) y comprueba que las citas de la IA existan en ellos.</summary>
public interface IDocumentosAsistente
{
    Task<IReadOnlyList<DocumentoCargadoAsistente>> CargarAsync(IReadOnlyList<DocumentoAsistenteMovil> documentos, CancellationToken ct);

    VerificacionCitaAsistente Verificar(byte[] pdf, int? pagina, string fragmento);
}
