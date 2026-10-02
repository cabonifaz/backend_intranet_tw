using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerContactosPorClienteCasoDeUso(IMaestrosRepositorio repositorio)
{
    public Task<RespuestaDto<List<ContactoClienteDto>>> EjecutarAsync(
        long idCliente, CancellationToken ct)
        => repositorio.ObtenerContactosPorClienteAsync(idCliente, ct);
}
