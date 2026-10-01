using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface ITextosBaseRepositorio
{
    Task<RespuestaDto<TextosBasePaginadoDto>> ObtenerTextosBaseAsync(
        string? busqueda, string? tipoCategoria, string? estado, bool soloPredeterminados,
        int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<TextoBaseDetalleDto>> ObtenerTextoBasePorIdAsync(
        long idTextoBase, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarTextoBaseAsync(
        GuardarTextoBaseDto dto, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoTextoBaseAsync(
        long idTextoBase, string estado, long idUsuario, CancellationToken ct);
}
