using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerSuministroPorIdCasoDeUso(ISuministrosRepositorio repositorio)
{
    public Task<RespuestaDto<SuministroDetalleDto>> EjecutarAsync(long idSuministro, CancellationToken ct = default)
        => repositorio.ObtenerSuministroPorIdAsync(idSuministro, ct);
}
