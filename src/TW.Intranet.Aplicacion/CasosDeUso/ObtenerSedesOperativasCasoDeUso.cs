using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerSedesOperativasCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<SedeOperativaDto>>> EjecutarAsync(CancellationToken ct = default)
        => repositorio.ObtenerSedesOperativasAsync(ct);
}
