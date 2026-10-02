using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoCategoriaCasoDeUso(IMaestrosRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(CambiarEstadoCategoriaDto dto, string usuMod, CancellationToken ct = default)
        => repositorio.CambiarEstadoCategoriaAsync(dto, usuMod, ct);
}
