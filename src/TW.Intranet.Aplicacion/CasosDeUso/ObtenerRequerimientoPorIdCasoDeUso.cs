using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerRequerimientoPorIdCasoDeUso(ICrmRepositorio repo)
{
    public Task<RespuestaDto<RequerimientoFichaDto>> EjecutarAsync(
        long idRequerimiento, CancellationToken ct)
        => repo.ObtenerRequerimientoPorIdAsync(idRequerimiento, ct);
}
