namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-37 — Agenda y carga del área (Jefe de Área) ───────────────────────────────────────────────────────────

/// <summary>
/// KPIs de la agenda. Conflictos = TODOS los conflictos de programación pendientes de los técnicos del alcance del jefe (el mismo número del menú de Jefatura y del banner); Servicios = los de
/// la semana mostrada; Sobrecargados = técnicos con sobrecarga en la semana o en algún día.
/// </summary>
public record AgendaKpisDto(int Conflictos, int Servicios, int Sobrecargados, string? Actualizado, int RefrescoSegundos);

/// <summary>
/// Un servicio (OS u OM) de un técnico en un día. Codigo = número corto de 4 cifras («0845»). Estado: confirmado | en_curso | demora | conflicto | pendiente | finalizado
/// (conflicto = está en un conflicto de la HU-39; demora = hoy con demora o incidencia en el seguimiento operativo, o la OS pausada; en_curso = en ruta, en ejecución o bloqueada;
/// confirmado = programado y confirmado por el cliente; pendiente = falta la confirmación del cliente o lo frena SSOMA / una solicitud de reprogramación).
/// </summary>
public record AgendaServicioDto(long IdOs, long? IdProgramacion, string NumeroOs, string Tipo, string Codigo, string? Cliente, string? HoraInicio, string? HoraFin, string? TipoServicio,
                                string Estado, bool Conflicto);

/// <summary>Un día de la semana de un técnico: horas programadas, nivel de carga (libre | baja | optima | alta | sobrecarga) y si algún servicio suyo se cruza con otro.</summary>
public record AgendaDiaDto(string Fecha, decimal Horas, string Nivel, bool Conflicto, List<AgendaServicioDto> Servicios);

/// <summary>Un técnico de la matriz. HorasSemana / UtilizacionPct / Nivel = su carga de la semana mostrada (capacidad = HORAS_JORNADA × DIAS_LABORABLES_SEMANA).</summary>
public record AgendaTecnicoDto(long IdUsuario, string Nombre, string NombreCorto, string Iniciales, List<AgendaDiaDto> Dias, decimal HorasSemana, int UtilizacionPct, string Nivel);

/// <summary>
/// Un conflicto de programación (HU-39). Tipo: solapamiento | extension_duracion | baja | ssoma_vencido. IdOsB solo en los cruces. PuedeResolver = el usuario tiene prog_gestionar.
/// Modo: directa (el jefe edita al instante) | solicitud (queda una solicitud de reprogramación pendiente) | solo_lectura (no puede resolver).
/// </summary>
public record AgendaConflictoDto(string Clave, string Tipo, string Titulo, string? Detalle, string? Fecha, long IdTecnico, string Tecnico, long? IdOsA, string? NumeroOsA, long? IdOsB,
                                 string? NumeroOsB, bool PuedeResolver, string Modo);

/// <summary>
/// Agenda de una semana. Desde = el lunes; Hasta = el viernes, o el domingo si algún técnico del alcance tiene servicios el sábado o el domingo. Las vistas Semana, Día y Carga se pintan con este
/// mismo contenido (Día = un día de Dias; Carga = Horas / Nivel / Utilización). Técnicos por nombre.
/// </summary>
public record AgendaAreaDto(string Desde, string Hasta, AgendaKpisDto Kpis, List<AgendaTecnicoDto> Tecnicos, List<AgendaConflictoDto> Conflictos);

/// <summary>
/// Un servicio del conflicto. Objetivo = el que conviene mover: entre los que tienen programación vigente, el menos avanzado (pendiente de confirmación del cliente antes que confirmado) y,
/// a igualdad, el más reciente (mayor id).
/// </summary>
public record AgendaConflictoServicioDto(long IdOs, long? IdProgramacion, string NumeroOs, string Tipo, string? Cliente, string? Fecha, string? HoraInicio, string? HoraFin, string? TipoServicio, bool Objetivo);

/// <summary>El técnico sugerido para «Cambiar técnico»: libre en la franja, con SSOMA conforme (o por vencer) y de tu alcance. Detalle: «carga 50 % · SSOMA conforme».</summary>
public record TecnicoSugeridoDto(long IdUsuario, string Nombre, string? Detalle);

/// <summary>Opción de un catálogo (motivos de reprogramación, MOTIVO_REPROGRAMACION).</summary>
public record OpcionAgendaDto(int Id, string Nombre);

/// <summary>Modal «Conflicto de programación»: el conflicto, sus servicios, el técnico sugerido y el catálogo de motivos. MotivoSugerido = el que autocompleta la HU-39.</summary>
public record AgendaConflictoDetalleDto(AgendaConflictoDto Conflicto, List<AgendaConflictoServicioDto> Servicios, TecnicoSugeridoDto? Sugerido, List<OpcionAgendaDto> Motivos, string Modo,
                                        string? MotivoSugerido);

/// <summary>
/// Resolver un conflicto. Opcion: reasignar (Cambiar técnico: IdNuevoTecnico) | reprogramar (Cambiar horario = la misma fecha con otras horas; Reprogramar con motivo = otra fecha y horas:
/// Fecha «yyyy-MM-dd», HoraInicio / HoraFin «HH:mm»). IdOsObjetivo = la orden a mover (por defecto IdOsA). IdMotivo opcional (si no viene, el del conflicto). Comentario hasta 400.
/// </summary>
public record ResolverConflictoAgendaDto(string? Tipo, long? IdTecnico, long? IdOsA, long? IdOsB, string? Opcion, long? IdOsObjetivo, long? IdNuevoTecnico, string? Fecha, string? HoraInicio,
                                         string? HoraFin, int? IdMotivo, string? Comentario);

/// <summary>Resultado: Modo directa (ya se aplicó) | solicitud (quedó pendiente de aprobación); Mensaje = el que responde la intranet.</summary>
public record ResolucionConflictoAgendaDto(string Modo, string Mensaje);
