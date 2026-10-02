using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerClientePorIdCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<ClienteDetalleDto>> EjecutarAsync(
        long idCliente, CancellationToken ct = default)
        => await repositorio.ObtenerClientePorIdAsync(idCliente, ct);
}
