using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IEquiposClienteRepositorio
{
    Task<RespuestaDto<EquiposClientePaginadoDto>> ObtenerEquiposAsync(
        string? busqueda, long? idCliente, long? idSede,
        string? clasificacion, string? estado, bool soloVigentesServicio,
        int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<EquipoClienteDetalleDto>> ObtenerEquipoPorIdAsync(long idEquipo, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarEquipoAsync(GuardarEquipoClienteDto dto, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoEquipoAsync(long idEquipo, string estado, long idUsuario, CancellationToken ct);
}
