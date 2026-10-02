using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerClientesCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<ClientesPaginadoDto>> EjecutarAsync(
        string? busqueda, string? estado, int pagina, int porPagina, CancellationToken ct = default)
        => await repositorio.ObtenerClientesAsync(busqueda, estado, pagina, porPagina, ct);
}
