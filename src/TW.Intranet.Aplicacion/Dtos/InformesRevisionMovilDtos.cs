namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-33 — Revisión de informes técnicos (Jefe de Área) ─────────────────────────────────────────────────────

/// <summary>
/// KPIs de "Informes por revisar" sobre todo el alcance del jefe (sin pestaña ni búsqueda): pendientes (por revisar), observados (en corrección), sin evidencias (por revisar sin fotos)
/// y SLA vencido (por revisar con más horas de espera que RT_SLA_REVISION_HORAS).
/// </summary>
public record InformesRevisionKpisDto(int Pendientes, int Observados, int SinEvidencias, int SlaVencido, string? Actualizado, int RefrescoSegundos);

/// <summary>
/// Un informe de la lista. Estado: por_revisar | en_correccion | aprobado. PlazoEn (ISO sin zona, hora de Lima) solo en corrección. FirmadoPorCliente: la OS ya tiene una firma de responsable.
/// Resumen lo arma la app (queda null).
/// </summary>
public record InformeRevisionItemDto(long IdInforme, string NumeroInforme, string? NumeroOs, string? Cliente, string? Equipo, string? CodigoTw, string? Tecnico, string Estado,
                                     int Evidencias, int Forzadas, bool FirmadoPorCliente, int HorasEspera, bool SlaVencido, string? PlazoEn, string? Resumen = null);

public record InformesRevisionDto(InformesRevisionKpisDto Kpis, List<InformeRevisionItemDto> Informes);

/// <summary>
/// Cabecera del informe. Estado: por_revisar | en_correccion | aprobado. PuedeAprobar / PuedeObservar los calcula el SP (permiso rt_revisar, estado, corrección pendiente y validaciones
/// obligatorias); MotivoBloqueo dice por qué no se puede aprobar. FechaEjecucion "yyyy-MM-dd"; FechaRevision ISO sin zona (hora de Lima).
/// </summary>
public record InformeRevisionCabeceraDto(long IdInforme, string NumeroInforme, string? TipoServicio, string? NumeroOs, string? Cliente, string? Sede, string? Equipo, string? CodigoTw,
                                         string? NumeroSerie, string? Tecnico, string? FechaEjecucion, string? Diagnostico, string Estado, bool SlaVencido, int HorasEspera,
                                         bool PuedeAprobar, bool PuedeObservar, string? MotivoBloqueo, string? Revisor, string? FechaRevision, string? Nota);

/// <summary>Validación del informe. Código: datos · ensayos · evidencias · procedimiento · precotizacion · firmas. Estado: ok | atencion | error. Obligatoria + error bloquea "Aprobar y liberar".</summary>
public record ValidacionInformeDto(string Codigo, string Titulo, string? Detalle, string Estado, bool Obligatoria);

/// <summary>Evidencia del informe (foto o video). Forzada = la IA la rechazó y el técnico la aceptó con un motivo (se resalta). Archivo: GET …/evidencias/{id}/archivo[?cuadro=true].</summary>
public record EvidenciaInformeDto(long IdEvidencia, string Etiqueta, bool Forzada, string? MotivoForzada, bool EsVideo, string? ValidacionIa);

/// <summary>Corrección pedida al técnico. Motivo y Secciones son códigos del catálogo; PlazoEn y CreadaEn ISO sin zona (hora de Lima).</summary>
public record CorreccionInformeDto(long IdCorreccion, string Motivo, string MotivoNombre, List<string> Secciones, string Instruccion, string? PlazoEn, string Estado, string? Por, string? CreadaEn);

public record OpcionRevisionInformeDto(string Codigo, string Nombre);

public record PlazoInformeDto(int Horas, string Texto);

/// <summary>Detalle de un informe + catálogos fijos del modal "Observar informe" (motivos, secciones y plazos).</summary>
public record InformeRevisionDetalleDto(InformeRevisionCabeceraDto Cabecera, List<ValidacionInformeDto> Validaciones, List<EvidenciaInformeDto> Evidencias, CorreccionInformeDto? Correccion,
                                        List<OpcionRevisionInformeDto> Motivos, List<OpcionRevisionInformeDto> Secciones, List<PlazoInformeDto> Plazos);

/// <summary>Observar: motivo (código), secciones afectadas (códigos, al menos una), qué debe corregir (10 a 1000 caracteres) y plazo en horas (4, 24, 48 o 72).</summary>
public record ObservarInformeDto(string? Motivo, List<string>? Secciones, string? Instruccion, int? PlazoHoras);

/// <summary>Aprobar y liberar: nota interna opcional (hasta 500 caracteres).</summary>
public record AprobarInformeDto(string? Nota);

public record ObservacionInformeResultadoDto(long IdCorreccion, string? PlazoEn, int Notificados);

public record AprobacionInformeResultadoDto(long IdInforme, string Estado);
