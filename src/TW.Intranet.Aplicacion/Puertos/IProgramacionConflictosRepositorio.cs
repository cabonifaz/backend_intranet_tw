using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-39 Carga de Recursos y Alertas de Conflicto Sobrevenido (Sprint 5).</summary>
public interface IProgramacionConflictosRepositorio
{
    Task<RespuestaDto<ConflictosProgramacionDto>> ObtenerConflictosAsync(long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ConflictoModalDto>>         ObtenerConflictoAsync(string tipo, long idTecnico, long idOsA, long? idOsB, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ReprogramacionResultadoDto>> ResolverConflictoAsync(ResolucionConflictoNormalizada n, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TecnicoDiaDto>>             ObtenerProgramacionesTecnicoDiaAsync(long idTecnico, DateTime fecha, long idUsuario, CancellationToken ct);
}
