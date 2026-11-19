using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Revisión de informes técnicos del Jefe de Área en la app móvil (App Mobile HU-33). Todo sale de procedimientos almacenados.</summary>
public interface IInformesRevisionMovilRepositorio
{
    Task<RespuestaDto<InformesRevisionDto>> ObtenerAsync(long idUsuario, string grupo, string? busqueda, CancellationToken ct);

    Task<RespuestaDto<InformeRevisionDetalleDto>> ObtenerDetalleAsync(long idUsuario, long idInforme, CancellationToken ct);

    Task<RespuestaDto<ArchivoAprobacionMovilDto>> ObtenerArchivoAsync(long idUsuario, long idInforme, long idEvidencia, CancellationToken ct);

    /// <summary>Observa el informe: secciones en códigos separados por coma (ya normalizadas).</summary>
    Task<RespuestaDto<ObservacionInformeResultadoDto>> ObservarAsync(long idUsuario, long idInforme, string motivo, string secciones, string instruccion, int plazoHoras, CancellationToken ct);

    Task<RespuestaDto<AprobacionInformeResultadoDto>> AprobarAsync(long idUsuario, long idInforme, string? nota, CancellationToken ct);
}
