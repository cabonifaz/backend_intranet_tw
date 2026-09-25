using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarContactoCasoDeUso(IMaestrosRepositorio repositorio)
{
    public Task<RespuestaDto<long>> EjecutarAsync(
        GuardarContactoDto dto, string usuCre, CancellationToken ct)
        => repositorio.GuardarContactoAsync(dto, usuCre, ct);
}
