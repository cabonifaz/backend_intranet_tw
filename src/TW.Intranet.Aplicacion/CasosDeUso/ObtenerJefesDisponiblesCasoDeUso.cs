using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerJefesDisponiblesCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<UsuarioListaItemDto>>> EjecutarAsync(CancellationToken ct = default)
        => repositorio.ObtenerJefesDisponiblesAsync(ct);
}
