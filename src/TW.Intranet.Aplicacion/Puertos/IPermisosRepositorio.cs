using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IPermisosRepositorio
{
    Task<RespuestaDto<List<PermisoModuloDto>>> ObtenerPermisosUsuarioAsync(long idUsuario, CancellationToken ct);
    Task<RespuestaDto<List<PermisoModuloDto>>> ObtenerPermisosAreaRolAsync(string area, string rol, CancellationToken ct);
    Task<RespuestaDto<bool>> GuardarPermisoAsync(GuardarPermisoDto dto, long idUsuario, CancellationToken ct);
}
