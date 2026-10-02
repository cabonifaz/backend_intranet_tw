using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerUsuarioPorIdCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<UsuarioDetalleDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => repositorio.ObtenerUsuarioPorIdAsync(idUsuario, ct);
}
