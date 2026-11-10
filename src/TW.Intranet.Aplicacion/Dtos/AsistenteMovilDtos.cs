namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-19 — Asistente IA y Procedimientos ───────────────────────────────────────────────────────────

/// <summary>El equipo que el técnico usa como contexto del asistente. Estado: por_iniciar | en_ejecucion | pausado | completado | observado.</summary>
public record ContextoAsistenteMovilDto(
    long    IdOs,
    string  NumeroOs,
    long    IdOsEquipo,
    string  Nombre,
    int     Numero,
    string? Marca,
    string? Modelo,
    string? CodigoCliente,
    string? NumeroSerie,
    string? ServicioSigla,
    string  Estado);

/// <summary>
/// Un documento oficial que consultará el asistente. IdDocumento: "M-{idSuministro}" (manual) o "P-{idProcedimiento}" (procedimiento aprobado).
/// Actualizado = "yyyy-MM-dd". Disponible = se puede leer (el manual debe ser una URL https).
/// </summary>
public record FuenteDisponibleAsistenteMovilDto(
    string  IdDocumento,
    string  Tipo,
    string  Titulo,
    string? Version,
    string? Entidad,
    string? Actualizado,
    bool    Disponible);

/// <summary>Consulta reciente del técnico: "Ajuste de excentricidad PBA430 · Hoy 10:20 · Manual PBA430 §6.4". Hora de Lima.</summary>
public record ConsultaRecienteAsistenteMovilDto(
    long      IdConsulta,
    string    Pregunta,
    string?   Fuente,
    DateTime? CreadoEn);

/// <summary>Inicio del asistente: equipo en contexto (null si no hay uno en trabajo), documentos que consultará, sugerencias (máx. 6) y las últimas 5 consultas.</summary>
public record InicioAsistenteMovilDto(
    ContextoAsistenteMovilDto?                     Contexto,
    List<FuenteDisponibleAsistenteMovilDto>        Fuentes,
    List<string>                                   Sugerencias,
    List<ConsultaRecienteAsistenteMovilDto>        Recientes);

/// <summary>Un equipo para "Cambiar" el contexto del asistente. EnTrabajo = está en ejecución. FuentesDisponibles = documentos oficiales consultables.</summary>
public record EquipoAsistenteMovilDto(
    long    IdOs,
    string  NumeroOs,
    long    IdOsEquipo,
    string  Nombre,
    int     Numero,
    string? Marca,
    string? Modelo,
    string? CodigoCliente,
    string  Estado,
    bool    EnTrabajo,
    int     FuentesDisponibles);

/// <summary>Lo que envía la app al consultar. Origen: texto | voz | sugerencia. La pregunta lleva de 3 a 500 caracteres.</summary>
public record PeticionConsultaAsistenteMovilDto(long? IdOs, long? IdOsEquipo, string? Pregunta, string? Origen);

/// <summary>
/// Una fuente de la respuesta: el documento oficial, la sección y la página citadas y el fragmento textual. Verificada = el back comprobó que el fragmento existe en el
/// PDF (true), que no existe en la página citada (false) o que el PDF no tiene texto y no se puede comprobar (null). En una respuesta sin resultado las fuentes
/// son los documentos consultados, sin sección, página ni fragmento (Fragmento = "").
/// </summary>
public record FuenteRespuestaAsistenteMovilDto(
    int     N,
    string  IdDocumento,
    string  Documento,
    string  Tipo,
    string? Entidad,
    string? Version,
    string? Actualizado,
    string? Seccion,
    int?    Pagina,
    string  Fragmento,
    bool?   Verificada);

/// <summary>
/// Respuesta del asistente: advertencia de seguridad, pasos y fuentes con la sección del manual oficial. Si Encontrada = false no hay advertencia ni pasos y
/// MotivoSinRespuesta dice por qué. Util = la valoración del técnico (null si no valoró). CreadoEn en hora de Lima.
/// </summary>
public record RespuestaAsistenteMovilDto(
    long                                      IdConsulta,
    long                                      IdOs,
    long                                      IdOsEquipo,
    string                                    Pregunta,
    string                                    Origen,
    DateTime?                                 CreadoEn,
    bool                                      Encontrada,
    string?                                   Advertencia,
    List<string>                              Pasos,
    List<FuenteRespuestaAsistenteMovilDto>    Fuentes,
    string?                                   MotivoSinRespuesta,
    bool?                                     Util);

/// <summary>Pantalla "Fuente consultada": el documento oficial, su sección y el fragmento que usó el asistente (y, si se pudo leer el PDF, lo que sigue en la página).</summary>
public record FuenteConsultadaAsistenteMovilDto(
    long    IdConsulta,
    int     N,
    string  IdDocumento,
    string  Documento,
    string  Tipo,
    bool    Oficial,
    string? Entidad,
    string? Version,
    string? Actualizado,
    int?    Pagina,
    string? Seccion,
    string? Advertencia,
    string  Fragmento,
    string? ContextoPosterior,
    bool?   Verificada);

public record PeticionValoracionAsistenteMovilDto(bool? Util);

public record TranscripcionVozAsistenteMovilDto(string Texto);

/// <summary>Un guardado del listado "Guardados". Tipo: respuesta | fragmento. TamanoBytes = lo que ocupa su contenido.</summary>
public record GuardadoAsistenteMovilDto(
    long      IdGuardado,
    string    Tipo,
    string    Titulo,
    string?   Subtitulo,
    DateTime? CreadoEn,
    int       TamanoBytes);

/// <summary>Guarda una respuesta (tipo = respuesta) o un fragmento citado (tipo = fragmento, con el número N de la fuente).</summary>
public record PeticionGuardarAsistenteMovilDto(long? IdConsulta, string? Tipo, int? N);

/// <summary>Un guardado con su contenido completo, para leerlo sin conexión: la respuesta (tipo respuesta) o la fuente (tipo fragmento).</summary>
public record GuardadoAsistenteCompletoMovilDto(
    long                          IdGuardado,
    string                        Tipo,
    string                        Titulo,
    string?                       Subtitulo,
    DateTime?                     CreadoEn,
    int                           TamanoBytes,
    RespuestaAsistenteMovilDto?   Respuesta,
    FuenteConsultadaAsistenteMovilDto? Fuente);
