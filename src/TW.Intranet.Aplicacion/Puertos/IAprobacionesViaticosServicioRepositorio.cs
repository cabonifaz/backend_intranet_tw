using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// HU-52 / HU-57 (Sprint 5) Aprobaciones y viáticos de una OS vistos desde el Seguimiento y desde la Revisión de Informes.
/// Cada SP valida el permiso, que el servicio/informe esté en el alcance del usuario y que lo pedido pertenezca a esa OS (anti-IDOR).
/// </summary>
public interface IAprobacionesViaticosServicioRepositorio
{
    Task<RespuestaDto<AprobacionesServicioDto>> ObtenerAprobacionesAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<bool>> ResolverAprobacionAsync(long idUsuario, long idOs, string tipo, long id, bool aprobar, string comentario, CancellationToken ct);
    Task<RespuestaDto<ViaticosOsDto>> ObtenerViaticosServicioAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoServicioAsync(long idUsuario, long idOs, long idGasto, string accion, string? comentario, CancellationToken ct);
    Task<RespuestaDto<string>> ObtenerRutaComprobanteAsync(long idUsuario, long idOs, long idGasto, int n, CancellationToken ct);
    Task<RespuestaDto<ViaticosOsDto>> ObtenerViaticosInformeAsync(long idUsuario, long idInforme, CancellationToken ct);
}
