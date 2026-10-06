using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Permisos por área + rol + módulo (reunión 02-oct).</summary>
public class PermisosRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IPermisosRepositorio
{
    public Task<RespuestaDto<List<PermisoModuloDto>>> ObtenerPermisosUsuarioAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPermisosUsuario",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            (r, mensaje) => LeerPermisosAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<List<PermisoModuloDto>>> ObtenerPermisosAreaRolAsync(string area, string rol, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPermisosAreaRol",
            p =>
            {
                p.AddWithValue("p_area", area);
                p.AddWithValue("p_rol",  rol);
            },
            (r, mensaje) => LeerPermisosAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<bool>> GuardarPermisoAsync(GuardarPermisoDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarPermisoAreaRol",
            p =>
            {
                p.AddWithValue("p_area",       dto.Area!);
                p.AddWithValue("p_rol",        dto.Rol!);
                p.AddWithValue("p_modulo",     dto.Modulo!);
                p.AddWithValue("p_acceso",     Valor(dto.Acceso));
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    private static async Task<RespuestaDto<List<PermisoModuloDto>>> LeerPermisosAsync(
        MySqlDataReader r, string mensaje, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var items = new List<PermisoModuloDto>();
        while (await r.ReadAsync(ct))
            items.Add(new PermisoModuloDto(
                Texto(r, "modulo") ?? "",
                Texto(r, "modulo_label") ?? "",
                Texto(r, "area_modulo") ?? "",
                Texto(r, "acceso") ?? "ninguno",
                Booleano(r, "es_excepcion")));
        return new RespuestaDto<List<PermisoModuloDto>>(2, mensaje, items);
    }
}
