using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerClientesCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<List<ClienteListaItemDto>>> EjecutarAsync(
        string? busqueda, string? estado, CancellationToken ct = default)
        => await repositorio.ObtenerClientesAsync(busqueda, estado, ct);
}
