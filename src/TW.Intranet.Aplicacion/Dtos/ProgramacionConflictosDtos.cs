namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-39 Carga de Recursos y Alertas de Conflicto Sobrevenido (Sprint 5) ─────────────────────────────────

/// <summary>Resumen de la lista de alertas: contadores por tipo y el circuito del usuario (directa | solicitud | solo_lectura).</summary>
public record ConflictosResumenDto(
    int Total, int Criticas, int Baja, int SsomaVencido, int Solapamiento, int ExtensionDuracion, string Modo, bool PuedeResolver);

/// <summary>Una alerta de la lista de arriba de la matriz. Identificada por su Clave (tipo + técnico + órdenes).</summary>
public record ConflictoDto(
    string Clave, string Tipo, string TipoLabel, string Severidad, string Titulo, string Detalle,
    long IdTecnico, string Tecnico, string? Fecha, int NServicios, long? IdOsA, long? IdOsB,
    string? SolapeInicio, string? SolapeFin, int? IdMotivoSugerido, string? MotivoSugerido, string Modo, bool PuedeResolver);

/// <summary>Servicio afectado por una alerta. Resoluble = tiene programación vigente (se puede reasignar o reprogramar).</summary>
public record ServicioAfectadoDto(
    string Clave, long IdOs, string NumeroOs, string Tipo, string? RazonSocial, string? TipoServicio, long? IdProgramacion,
    string? EstadoProgramacion, string? Fecha, string? HoraInicio, string? HoraFin, bool Resoluble);

public record ConflictosProgramacionDto(
    ConflictosResumenDto Resumen, IReadOnlyList<ConflictoDto> Conflictos, IReadOnlyList<ServicioAfectadoDto> Servicios);

// ── Modal "Resolver Conflicto de Programación" ──

public record ConflictoDetalleDto(
    string Clave, string Tipo, string Severidad, string Titulo, string Detalle, long IdTecnico, string Tecnico, string? Cargo,
    string? SedeOperativa, string? Fecha, string? SolapeInicio, string? SolapeFin, int SolapeMinutos, string? ImpactoOperativo,
    int? IdMotivoSugerido, string? MotivoSugerido, string Modo, bool PuedeResolver);

public record ServicioConflictoDto(
    int Orden, string Etiqueta, long IdOs, long? IdProgramacion, string NumeroOs, string Tipo, string? RazonSocial, string? TipoServicio,
    string? EstadoProgramacion, string? EstadoLabel, string? Fecha, string? HoraInicio, string? HoraFin, decimal? Horas, bool Resoluble);

public record OpcionResolucionDto(
    string Codigo, string Titulo, string Descripcion, long? AfectaIdOs, long? AfectaIdProgramacion, bool MantieneConfirmado,
    bool VuelvePendienteCliente, bool Disponible, string? MotivoNoDisponible);

public record RecursoSugeridoDto(
    long ParaIdOs, string ParaNumero, long IdTecnico, string Nombre, string? Cargo, string? TipoRecurso, string? SedeOperativa,
    string? SsomaEstado, decimal HorasSemana, int UtilizacionPct, int Score);

public record ConflictoModalDto(
    ConflictoDetalleDto Conflicto, IReadOnlyList<ServicioConflictoDto> Servicios, IReadOnlyList<OpcionResolucionDto> Opciones,
    IReadOnlyList<RecursoSugeridoDto> Recursos);

/// <summary>Cuerpo de "Aplicar Resolución". El circuito (directa o solicitud) lo decide el servidor con el permiso del usuario.</summary>
public class ResolverConflictoDto
{
    public string?   Tipo           { get; set; }
    public long      IdTecnico      { get; set; }
    public long      IdOsA          { get; set; }
    public long?     IdOsB          { get; set; }
    public string?   Opcion         { get; set; }   // reasignar | reprogramar
    public long?     IdOsObjetivo   { get; set; }
    public long?     IdNuevoTecnico { get; set; }   // reasignar
    public DateTime? Fecha          { get; set; }   // reprogramar
    public string?   HoraInicio     { get; set; }
    public string?   HoraFin        { get; set; }
    public string?   Comentario     { get; set; }
}

public record ResolucionConflictoNormalizada(
    string Tipo, long IdTecnico, long IdOsA, long? IdOsB, string Opcion, long? IdOsObjetivo, long? IdNuevoTecnico,
    DateTime? Fecha, TimeSpan? HoraInicio, TimeSpan? HoraFin, string? Comentario);

// ── Panel lateral de la celda (técnico + día) ──

public record CargaDiaTecnicoDto(
    long IdTecnico, string Tecnico, string? Cargo, string? SedeOperativa, string EstadoUsuario, string Fecha, decimal Horas, int Servicios,
    bool Conflicto, string Nivel, bool PuedeGestionar);

public record ProgramacionDiaDto(
    long IdOs, string Tipo, string NumeroOs, string EstadoOs, string? SubEstado, string Rol, long? IdProgramacion, string? Codigo,
    string? EstadoProgramacion, string? EstadoProgramacionLabel, string? RazonSocial, string? Sede, string? TipoServicio,
    string? HoraInicio, string? HoraFin, decimal? Horas, bool EnConflicto, bool SolicitudPendiente);

public record TecnicoDiaDto(CargaDiaTecnicoDto Carga, IReadOnlyList<ProgramacionDiaDto> Programaciones);
