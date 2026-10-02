using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerPropuestaPorIdCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<PropuestaDetalleDto>> EjecutarAsync(long idPropuesta, CancellationToken ct = default)
        => repositorio.ObtenerPropuestaPorIdAsync(idPropuesta, ct);
}
