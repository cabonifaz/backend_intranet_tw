using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarSedeCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarSedeDto dto, string usuCre, CancellationToken ct = default)
        => await repositorio.GuardarSedeAsync(dto, usuCre, ct);
}
