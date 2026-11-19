namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-36 — Mi equipo: asistencia y ubicación (Jefe de Área) + horas contabilizadas ────────────────────────────

/// <summary>
/// KPIs de «Mi equipo» (hoy, hora de Lima). Cada técnico cae en UN solo estado: EnLabores · Refrigerio · Tardanza · SinMarcar · Finalizaron. Total = todos los técnicos que ve el jefe.
/// EnJornada = EnLabores + Tardanza + Refrigerio (los que están en su jornada ahora): es el «N de M en labores» del menú de Jefatura.
/// </summary>
public record EquipoKpisDto(int EnLabores, int Refrigerio, int Tardanza, int SinMarcar, int Finalizaron, int Total, string? Actualizado, int RefrescoSegundos, int EnJornada = 0);

/// <summary>
/// Un técnico del equipo. Estado (Reloj marcador, HU-20): en_labores | refrigerio | tardanza | sin_marcar | finalizada. Detalle = el texto armado («En labores · 07:58 (tardanza 13 min)»,
/// «En refrigerio desde 10:30 · vuelve 11:15», «Sin marcar inicio de labores»). El servicio actual (IdOs, NumeroOs, TipoOs «OS» | «OM», EstadoServicio del seguimiento operativo: sin_salir · en_ruta ·
/// en_planta · en_ejecucion · con_demora · con_incidente · finalizado, Lugar = la planta) es null sin servicio; entonces MotivoSinServicio dice por qué (SSOMA bloqueado o documentos faltantes).
/// Latitud / Longitud / MinutosUbicacion: la última posición GPS de hoy (null si no envió).
/// </summary>
public record EquipoTecnicoDto(long IdUsuario, string Nombre, string Iniciales, string? Cargo, string Estado, string Detalle, string? HoraInicio, int? MinutosTardanza,
                               long? IdOs, string? NumeroOs, string? TipoOs, string? EstadoServicio, string? Lugar, string? MotivoSinServicio,
                               decimal? Latitud, decimal? Longitud, int? MinutosUbicacion);

public record EquipoJefaturaDto(EquipoKpisDto Kpis, List<EquipoTecnicoDto> Tecnicos);

/// <summary>SSOMA del técnico (SP_EvaluarSsomaProgramacion): conforme | por_vencer | incompleto | pendiente | bloqueado (null si no se pudo evaluar). Detalle: qué documento falta o está bloqueado.</summary>
public record SsomaTecnicoDto(string? Estado, string? Detalle);

/// <summary>Marcación del día (línea de tiempo del Reloj marcador). Estado: hecho | pendiente. Tono: verde | naranja | rojo | gris. Hora «HH:mm» (null si está pendiente).</summary>
public record MarcacionEquipoDto(string Tipo, string Titulo, string? Hora, string? Detalle, string Estado, string Tono);

/// <summary>Carga de un día de la semana: horas programadas y su porcentaje sobre la jornada (HORAS_JORNADA; puede pasar de 100). Etiqueta: Lun a Vie (y Sáb si tiene servicios).</summary>
public record CargaDiaEquipoDto(string Fecha, string Etiqueta, decimal Horas, int Porcentaje);

/// <summary>Carga de la semana: horas programadas de lunes a viernes contra la capacidad (5 × HORAS_JORNADA). Nivel: baja (menos de 50 %) | normal (50 a 84 %) | alta (85 % o más).</summary>
public record CargaSemanaDto(string Desde, string Hasta, List<CargaDiaEquipoDto> Dias, int UtilizacionPct, string Nivel, decimal HorasPlanificadas, decimal HorasCapacidad);

/// <summary>Ficha del técnico: lo de la lista + teléfono (para llamar) y área, su SSOMA, las marcaciones del día y la carga de la semana.</summary>
public record FichaEquipoTecnicoDto(EquipoTecnicoDto Tecnico, string? Telefono, string? Area, SsomaTecnicoDto Ssoma, List<MarcacionEquipoDto> Marcaciones, CargaSemanaDto Carga);

// ── Horas contabilizadas ─────────────────────────────────────────────────────────────────────────────────────────────

/// <summary>Un servicio dentro de un día: inicio y fin «HH:mm» (Fin null = sin cierre; «24:00» si siguió después de la medianoche) y los minutos de ese día.</summary>
public record HoraServicioDto(long IdOs, string Numero, string Inicio, string? Fin, int Minutos);

/// <summary>
/// Horas de un día con actividad. Minutos = tiempo en servicio (unión de los servicios, sin doble conteo). Inicio / Fin = primera hora de inicio y última de fin del día.
/// SinCierre = hubo un servicio iniciado y nunca cerrado (no se inventa su duración: cuenta 0).
/// </summary>
public record HoraDiaDto(string Fecha, int Minutos, int Servicios, string? Inicio, string? Fin, bool SinCierre, List<HoraServicioDto> Detalle);

/// <summary>Acumulado de una semana (lunes a domingo; Desde/Hasta son las fechas de la semana completa, pero los Minutos cuentan solo los días del mes consultado).</summary>
public record HoraSemanaDto(string Desde, string Hasta, int Minutos, int DiasTrabajados);

/// <summary>Un mes del historial guardado (Mes «AAAA-MM»). Cerrado = el mes ya pasó y quedó como foto.</summary>
public record HoraMesDto(string Mes, int Minutos, int DiasTrabajados, int Servicios, bool Cerrado);

/// <summary>
/// Horas contabilizadas de un técnico en un mes: calendario (Dias: solo los días con datos), acumulado por semana, total del mes e Historial de meses guardados (más reciente primero, máx. 24).
/// Las horas son «desde que inicia el servicio hasta que finaliza» (SP_ConsolidarHorasTecnicoMovil documenta la fuente y los casos borde).
/// </summary>
public record HorasTecnicoDto(EquipoTecnicoDto Tecnico, string Mes, List<HoraDiaDto> Dias, List<HoraSemanaDto> Semanas, int TotalMinutos, int DiasTrabajados, int Servicios, bool Cerrado,
                              List<HoraMesDto> Historial);
