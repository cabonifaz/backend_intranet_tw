using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface ISuministrosRepositorio
{
    Task<RespuestaDto<SuministrosPaginadoDto>> ObtenerSuministrosAsync(
        string? busqueda, string? clase, string? tipo, string? estado, bool soloEnPropuestas,
        int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<SuministroDetalleDto>> ObtenerSuministroPorIdAsync(
        long idSuministro, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarSuministroAsync(
        GuardarSuministroDto dto, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoSuministroAsync(
        long idSuministro, string estado, long idUsuario, CancellationToken ct);
}
