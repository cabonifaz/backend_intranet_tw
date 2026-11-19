using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Datos de una resolución ya validados y normalizados (tipos, ids y horas en su forma final).</summary>
public record ResolucionConflictoDatos(string Tipo, long IdTecnico, long IdOsA, long? IdOsB, string Opcion, long? IdOsObjetivo, long? IdNuevoTecnico,
                                       DateOnly? Fecha, TimeOnly? HoraInicio, TimeOnly? HoraFin, int? IdMotivo, string? Comentario);

/// <summary>Agenda y carga del área del Jefe de Área en la app móvil (App Mobile HU-37). Todo sale de procedimientos almacenados que envuelven la Programación de la intranet.</summary>
public interface IAgendaAreaMovilRepositorio
{
    /// <summary>desde = el lunes «yyyy-MM-dd» ya normalizado (null = la semana actual de Lima).</summary>
    Task<RespuestaDto<AgendaAreaDto>> ObtenerAsync(long idUsuario, string? desde, CancellationToken ct);

    Task<RespuestaDto<AgendaConflictoDetalleDto>> ObtenerConflictoAsync(long idUsuario, string tipo, long idTecnico, long idOsA, long? idOsB, CancellationToken ct);

    Task<RespuestaDto<ResolucionConflictoAgendaDto>> ResolverAsync(long idUsuario, ResolucionConflictoDatos datos, CancellationToken ct);
}
