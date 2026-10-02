using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerCatalogosRequerimientoCasoDeUso(ICrmRepositorio repo)
{
    public Task<RespuestaDto<CatalogosRequerimientoDto>> EjecutarAsync(CancellationToken ct)
        => repo.ObtenerCatalogosAsync(ct);
}
