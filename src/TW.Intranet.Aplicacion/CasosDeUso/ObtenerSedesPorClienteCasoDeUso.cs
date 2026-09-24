using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerSedesPorClienteCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<List<SedeClienteDto>>> EjecutarAsync(
        long idCliente, CancellationToken ct = default)
        => await repositorio.ObtenerSedesPorClienteAsync(idCliente, ct);
}
