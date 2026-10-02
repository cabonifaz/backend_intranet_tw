using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerCatalogoCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<List<CatalogoItemDto>>> EjecutarAsync(
        string descripcion, CancellationToken ct = default)
        => await repositorio.ObtenerCatalogoAsync(descripcion, ct);
}
