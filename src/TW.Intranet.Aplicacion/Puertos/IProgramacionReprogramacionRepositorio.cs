using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-38 Reprogramación y Cancelación de la Programación (Sprint 5).</summary>
public interface IProgramacionReprogramacionRepositorio
{
    Task<RespuestaDto<ProgramacionPreparadaDto>>     PrepararReprogramacionAsync(long idProgramacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ReprogramacionResultadoDto>>   ReprogramarAsync(NuevaReprogramacion n, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<SolicitudReprogramacionDto>>   ObtenerSolicitudAsync(long idSolicitud, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<SolicitudResueltaDto>>         ResolverSolicitudAsync(ResolucionSolicitudNormalizada n, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<SolicitudResueltaDto>>         RetirarSolicitudAsync(long idSolicitud, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<CancelacionPreparadaDto>>      PrepararCancelacionAsync(long idProgramacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<CancelacionResultadoDto>>      CancelarAsync(NuevaCancelacion n, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<HistorialProgramacionesOsDto>> ObtenerHistorialOsAsync(long idOs, long idUsuario, CancellationToken ct);
}
