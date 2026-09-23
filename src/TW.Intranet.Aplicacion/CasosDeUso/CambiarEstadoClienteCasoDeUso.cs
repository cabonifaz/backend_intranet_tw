using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoClienteCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoClienteDto dto, string usuMod, CancellationToken ct = default)
        => await repositorio.CambiarEstadoClienteAsync(dto, usuMod, ct);
}
