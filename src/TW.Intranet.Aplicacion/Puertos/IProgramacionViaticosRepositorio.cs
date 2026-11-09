using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-45 Asignación de Viáticos y Rendición de Gastos Operativos (Sprint 5).</summary>
public interface IProgramacionViaticosRepositorio
{
    Task<RespuestaDto<ViaticosProgramacionDto>>      ObtenerAsync(long idProgramacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<GuardarViaticosResultadoDto>>  GuardarAsync(long idProgramacion, GuardarViaticosNormalizado n, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<RevisarGastoResultadoDto>>     RevisarGastoAsync(long idProgramacion, long idGasto, string accion, string? comentario, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<CerrarRendicionResultadoDto>>  CerrarRendicionAsync(long idProgramacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ComprobanteGastoDto>>          ObtenerComprobanteAsync(long idProgramacion, long idGasto, long idUsuario, CancellationToken ct);
}
