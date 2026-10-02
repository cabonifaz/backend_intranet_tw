using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarCategoriaCasoDeUso(IMaestrosRepositorio repositorio)
{
    public Task<RespuestaDto<long>> EjecutarAsync(GuardarCategoriaDto dto, string usuCre, CancellationToken ct = default)
        => repositorio.GuardarCategoriaAsync(dto, usuCre, ct);
}
