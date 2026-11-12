using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// App Mobile HU-27 (rendir gastos) y HU-31 (bandeja del jefe: evidencias forzadas, ensayos con error y gastos).
/// Cada SP valida quién puede: el técnico solo sus gastos; el jefe según el área de la RQ (evidencia, ensayo) o prog_aprobar_reprogramacion (gasto).
/// </summary>
public interface IGastosAprobacionesMovilRepositorio
{
    // Técnico
    Task<RespuestaDto<ResultadoGastoMovilDto>> RendirGastoAsync(long idUsuario, ComandoGastoMovil comando, CancellationToken ct);
    Task<RespuestaDto<string>> ObtenerRutaFotoGastoAsync(long idUsuario, long idGasto, int n, CancellationToken ct);

    // Jefe
    Task<RespuestaDto<List<AprobacionMovilDto>>> ObtenerAprobacionesExtraAsync(long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DetalleAprobacionMovilDto>> ObtenerDetalleAsync(long idUsuario, string tipo, long id, CancellationToken ct);
    Task<RespuestaDto<ArchivoAprobacionMovilDto>> ObtenerArchivoAsync(long idUsuario, string tipo, long id, int n, CancellationToken ct);
    Task<RespuestaDto<bool>> ResolverEvidenciaAsync(long idUsuario, long idEvidencia, bool aprobar, string? comentario, CancellationToken ct);
    Task<RespuestaDto<bool>> ResolverEnsayoAsync(long idUsuario, long idInforme, bool aprobar, string? comentario, CancellationToken ct);
    Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoAsync(long idUsuario, long idGasto, string accion, string? comentario, CancellationToken ct);
}
