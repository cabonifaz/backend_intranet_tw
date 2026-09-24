using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoContactoCasoDeUso(IMaestrosRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoContactoDto dto, string usuMod, CancellationToken ct)
        => repositorio.CambiarEstadoContactoAsync(dto, usuMod, ct);
}
