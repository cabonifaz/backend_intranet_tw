using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IMaestrosRepositorio
{
    Task<RespuestaDto<List<ClienteListaItemDto>>> ObtenerClientesAsync(
        string? busqueda, string? estado, CancellationToken ct);

    Task<RespuestaDto<ClienteDetalleDto>> ObtenerClientePorIdAsync(
        long idCliente, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarClienteAsync(
        GuardarClienteDto dto, string usuCre, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoClienteAsync(
        CambiarEstadoClienteDto dto, string usuMod, CancellationToken ct);

    Task<RespuestaDto<List<CatalogoItemDto>>> ObtenerCatalogoAsync(
        string descripcion, CancellationToken ct);
}
