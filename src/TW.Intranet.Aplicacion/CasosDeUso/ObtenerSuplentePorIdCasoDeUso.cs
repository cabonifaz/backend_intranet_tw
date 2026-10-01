using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerSuplentePorIdCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<SuplenteListaItemDto>> EjecutarAsync(long idAsignacion, CancellationToken ct = default)
        => repositorio.ObtenerSuplentePorIdAsync(idAsignacion, ct);
}
