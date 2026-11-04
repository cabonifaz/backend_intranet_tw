namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-38 Reprogramación y Cancelación de la Programación (Sprint 5) ─────────────────────────────────────

/// <summary>Cuerpo de "Reprogramar". Lo que no se envía (null) se mantiene. El circuito (directa o solicitud) lo decide el servidor.</summary>
public class ReprogramarProgramacionDto
{
    public DateTime?   Fecha              { get; set; }
    public string?     HoraInicio         { get; set; }
    public string?     HoraFin            { get; set; }
    public long?       IdTecnicoPrincipal { get; set; }
    public List<long>? IdsTecnicosApoyo   { get; set; }
    public List<long>? IdsEquipos         { get; set; }
    public int         IdMotivo           { get; set; }
    public string?     Comentario         { get; set; }
}

/// <summary>Reprogramación ya validada que recibe el repositorio.</summary>
public record NuevaReprogramacion(
    long IdProgramacion, DateTime? Fecha, TimeSpan? HoraInicio, TimeSpan? HoraFin, long? IdTecnicoPrincipal,
    IReadOnlyList<long>? IdsApoyo, IReadOnlyList<long>? IdsEquipos, int IdMotivo, string? Comentario);

public record ReprogramacionResultadoDto(
    string  Modo,                     // directa | solicitud
    long?   IdSolicitud,
    long    IdProgramacion,
    string  Codigo,
    string  Estado,
    string  EstadoLabel,
    bool    RequiereReconfirmarCliente,
    bool    CambiaFechaHora,
    bool    CambiaTecnicos,
    bool    CambiaEquipos,
    string? FechaEjecucion,
    string? HoraInicio,
    string? HoraFin);

public class ResolverSolicitudDto
{
    public string? Decision   { get; set; }   // aprobar | rechazar
    public string? Comentario { get; set; }   // obligatorio al rechazar
}

public record ResolucionSolicitudNormalizada(long IdSolicitud, string Decision, string? Comentario);

public record SolicitudResueltaDto(
    long   IdSolicitud,
    string EstadoSolicitud,           // aprobada | rechazada | cancelada
    long   IdProgramacion,
    string Codigo,
    string Estado,
    string EstadoLabel,
    bool   RequiereReconfirmarCliente);

public record MotivoDto(int IdMotivo, string Nombre, string? Codigo);

public record TecnicoReprogramacionDto(long IdUsuario, string Nombre, string? Cargo, string Rol);

public record EquipoReprogramacionDto(long IdEquipo, string? CodigoTw, string? Marca, string? Modelo, string? NumSerie, bool Reservado);

public record ProgramacionPreparadaDto(
    long    IdProgramacion,
    string  Codigo,
    string  Estado,
    string  EstadoLabel,
    long    IdOs,
    string  NumeroOs,
    string  Tipo,
    string? EstadoOs,
    string? RazonSocial,
    string? Sede,
    string? Ubicacion,
    string? TipoServicio,
    string? FechaEjecucion,
    string? HoraInicio,
    string? HoraFin,
    decimal? DuracionHoras,
    long?   IdTecnicoPrincipal,
    string? TecnicoPrincipal,
    int     NumeroEquipos,
    decimal ViaticosDepositados,
    string  Modo,                     // directa | solicitud
    long?   IdSolicitudPendiente,
    bool    PuedeReprogramar,
    string? MotivoNoReprogramable,
    int     ComentarioMaximo,
    IReadOnlyList<TecnicoReprogramacionDto> Tecnicos,
    IReadOnlyList<EquipoReprogramacionDto>  Equipos,
    IReadOnlyList<MotivoDto> Motivos);

public record SolicitudReprogramacionDto(
    long    IdSolicitud,
    string  Estado,
    string  EstadoLabel,
    long    IdProgramacion,
    string  Codigo,
    long    IdOs,
    string  NumeroOs,
    string? RazonSocial,
    string? Solicitante,
    string? CargoSolicitante,
    DateTime? FechaSolicitud,
    string? Motivo,
    string? Comentario,
    string? FechaActual,
    string? HoraInicioActual,
    string? HoraFinActual,
    decimal? DuracionActualHoras,
    string? TecnicoActual,
    string? FechaPropuesta,
    string? HoraInicioPropuesta,
    string? HoraFinPropuesta,
    decimal? DuracionPropuestaHoras,
    int?    DiasDiferencia,
    string? TecnicoPropuesto,
    bool    CambiaTecnicoPrincipal,
    bool    ProponeApoyo,
    bool    ProponeEquipos,
    bool    CambiaFechaHora,
    string? NuevoEstadoLabel,
    decimal ViaticosDepositados,
    string? ResueltoPorNombre,
    DateTime? FechaResolucion,
    string? ComentarioResolucion,
    bool    PuedeResolver,
    bool    PuedeRetirar,
    IReadOnlyList<TecnicoReprogramacionDto> EquipoTrabajoPropuesto,
    IReadOnlyList<EquipoReprogramacionDto>  EquiposPropuestos);

public class CancelarProgramacionDto
{
    public int     IdMotivo   { get; set; }
    public string? Comentario { get; set; }
}

public record NuevaCancelacion(long IdProgramacion, int IdMotivo, string? Comentario);

public record CancelacionPreparadaDto(
    long    IdProgramacion,
    string  Codigo,
    string  Estado,
    string  EstadoLabel,
    long    IdOs,
    string  NumeroOs,
    string  Tipo,
    string? EstadoOs,
    string? RazonSocial,
    bool    PuedeCancelar,
    string? MotivoNoCancelable,
    decimal ViaticosDepositados,
    long?   IdSolicitudPendiente,
    int     ComentarioMinimo,
    int     ComentarioMaximo,
    IReadOnlyList<MotivoDto> Motivos);

public record CancelacionResultadoDto(
    long    IdProgramacion,
    string  Codigo,
    string  Estado,
    string  EstadoLabel,
    long    IdOs,
    string  NumeroOs,
    string? EstadoOs,
    string? Motivo,
    decimal ViaticosDepositados,
    int     SolicitudesCanceladas,
    string? SiguienteAccion);

public record ProgramacionHistorialDto(
    long    IdProgramacion,
    string  Codigo,
    string  Estado,
    string  EstadoLabel,
    bool    EsActiva,
    string? FechaEjecucion,
    string? HoraInicio,
    string? HoraFin,
    string? TecnicoPrincipal,
    DateTime? CreadoEn,
    string? CreadoPor,
    DateTime? CanceladaEn,
    string? CanceladaPor,
    string? MotivoCancelacion,
    string? ComentarioCancelacion,
    int     NumeroSolicitudes,
    int     NumeroReprogramaciones,
    IReadOnlyList<EventoHistorialProgramacionDto> Timeline);

public record EventoHistorialProgramacionDto(
    DateTime? Fecha, string? Tipo, string? Titulo, string? Descripcion, string? Usuario,
    string? EstadoAnterior, string? EstadoNuevo, string? Motivo);

public record HistorialProgramacionesOsDto(long IdOs, IReadOnlyList<ProgramacionHistorialDto> Programaciones);
