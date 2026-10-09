using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-13 / HU-14 — Visto bueno: bandeja, resolución, validaciones, comparación y costos.</summary>
public interface IVistoBuenoRepositorio
{
    Task<RespuestaDto<BandejaVistoBuenoDto>>      ObtenerBandejaAsync(FiltrosBandejaVistoBuenoDto f, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ResultadoResolverVistoBuenoDto>> ResolverAsync(long idPropuesta, ResolverVistoBuenoDto dto, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DecisionVistoBuenoDto>>     PrepararDecisionAsync(long idPropuesta, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<CorreccionPropuestaDto?>>   ObtenerCorreccionAsync(long idPropuesta, CancellationToken ct);
    Task<RespuestaDto<ReasignacionVistoBuenoDto>> PrepararReasignacionAsync(long idPropuesta, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<List<CandidatoAprobadorDto>>> ObtenerCandidatosReasignacionAsync(long idPropuesta, string? buscar, CancellationToken ct);
    Task<RespuestaDto<ResultadoReasignacionVbDto>> ReasignarAsync(long idPropuesta, ReasignarVistoBuenoDto dto, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<(List<ValidacionPreviaDto> Validaciones, ResumenEconomicoVbDto Resumen)>> ObtenerValidacionesAsync(long idPropuesta, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DatosComparacionDto>>       ObtenerDatosComparacionAsync(long idBase, long idDestino, CancellationToken ct);
    Task<RespuestaDto<CostoSuministroDto>>        ObtenerCostoSuministroAsync(long idSuministro, CancellationToken ct);
    Task<RespuestaDto<bool>>                      GuardarCostoSuministroAsync(long idSuministro, decimal? precioCosto, long idUsuario, CancellationToken ct);
}
