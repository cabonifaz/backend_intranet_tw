using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoSedeCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoSedeDto dto, string usuMod, CancellationToken ct = default)
        => await repositorio.CambiarEstadoSedeAsync(dto, usuMod, ct);
}
