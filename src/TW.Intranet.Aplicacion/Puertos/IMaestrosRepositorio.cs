using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IMaestrosRepositorio
{
    Task<RespuestaDto<ClientesPaginadoDto>> ObtenerClientesAsync(
        string? busqueda, string? estado, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<ClienteDetalleDto>> ObtenerClientePorIdAsync(
        long idCliente, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarClienteAsync(
        GuardarClienteDto dto, string usuCre, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoClienteAsync(
        CambiarEstadoClienteDto dto, string usuMod, CancellationToken ct);

    Task<RespuestaDto<List<CatalogoItemDto>>> ObtenerCatalogoAsync(
        string descripcion, CancellationToken ct);

    // ── Sedes ─────────────────────────────────────────────────────────────────

    Task<RespuestaDto<List<SedeClienteDto>>> ObtenerSedesPorClienteAsync(
        long idCliente, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarSedeAsync(
        GuardarSedeDto dto, string usuCre, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoSedeAsync(
        CambiarEstadoSedeDto dto, string usuMod, CancellationToken ct);

    // ── Contactos ─────────────────────────────────────────────────────────────

    Task<RespuestaDto<List<ContactoClienteDto>>> ObtenerContactosPorClienteAsync(
        long idCliente, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarContactoAsync(
        GuardarContactoDto dto, string usuCre, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoContactoAsync(
        CambiarEstadoContactoDto dto, string usuMod, CancellationToken ct);

    // ── Categorías de cliente ─────────────────────────────────────────────────

    Task<RespuestaDto<List<CategoriaClienteDto>>> ObtenerCategoriasAsync(CancellationToken ct);

    Task<RespuestaDto<long>> GuardarCategoriaAsync(
        GuardarCategoriaDto dto, string usuCre, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoCategoriaAsync(
        CambiarEstadoCategoriaDto dto, string usuMod, CancellationToken ct);
}
