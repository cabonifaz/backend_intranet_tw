using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarClienteCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarClienteDto dto, string usuCre, CancellationToken ct = default)
        => await repositorio.GuardarClienteAsync(dto, usuCre, ct);
}
