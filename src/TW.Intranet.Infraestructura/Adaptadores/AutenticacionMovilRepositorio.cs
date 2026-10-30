using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Dominio.Entidades;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Acceso y sesiones de la app móvil de campo (App Mobile HU-01).</summary>
public class AutenticacionMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IAutenticacionMovilRepositorio
{
    public Task<RespuestaDto<Usuario>> ObtenerPorNombreUsuarioAsync(string nombreUsuario, CancellationToken ct) =>
        EjecutarAsync<Usuario>("SP_ObtenerUsuarioPorNombreUsuario",
            p => p.AddWithValue("p_nombre_usuario", nombreUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new(3, "El procedimiento no devolvió datos del usuario.");

                var usuario = new Usuario
                {
                    IdUsuario              = EnteroLargo(r, "id_usuario"),
                    NombreUsuario          = Texto(r, "nombre_usuario") ?? string.Empty,
                    Nombre                 = Texto(r, "nombre") ?? string.Empty,
                    Apellido               = Texto(r, "apellido") ?? string.Empty,
                    Correo                 = Texto(r, "correo") ?? string.Empty,
                    PasswordHash           = Texto(r, "password_hash") ?? string.Empty,
                    RolSistema             = Texto(r, "rol_sistema") ?? string.Empty,
                    CanalAcceso            = Texto(r, "canal_acceso") ?? string.Empty,
                    Estado                 = Texto(r, "estado") ?? string.Empty,
                    Cargo                  = Texto(r, "cargo"),
                    Area                   = Texto(r, "area"),
                    ForzarCambioContrasena = Booleano(r, "forzar_cambio_contrasena"),
                };
                return new(2, mensaje, usuario);
            }, ct);

    public Task<RespuestaDto<SesionMovilDto>> IniciarSesionAsync(
        long idUsuario, string idDispositivo, string? nombreDispositivo, string? ipOrigen,
        int horasExpiracion, bool reemplazarSesion, CancellationToken ct) =>
        EjecutarAsync<SesionMovilDto>("SP_IniciarSesionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",         idUsuario);
                p.AddWithValue("p_id_dispositivo",     Recortar(idDispositivo, 100));
                p.AddWithValue("p_nombre_dispositivo", Valor(Recortar(nombreDispositivo, 150)));
                p.AddWithValue("p_ip_origen",          Valor(Recortar(ipOrigen, 45)));
                p.AddWithValue("p_horas_expiracion",   horasExpiracion);
                p.AddWithValue("p_reemplazar_sesion",  Bit(reemplazarSesion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new(3, "El procedimiento no devolvió la sesión.");

                return new(2, mensaje, new SesionMovilDto(
                    Texto(r, "sesion_token") ?? string.Empty,
                    FechaHora(r, "fecha_expiracion") ?? DateTime.Now.AddHours(horasExpiracion)));
            }, ct);

    public async Task<bool> VerificarSesionAsync(long idUsuario, string sesionToken, CancellationToken ct)
    {
        var r = await EjecutarAsync<bool>("SP_VerificarSesionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_sesion_token", sesionToken);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

        return r.IdTipoMensaje == 2;
    }

    public Task<RespuestaDto<bool>> CerrarSesionAsync(long idUsuario, string sesionToken, CancellationToken ct) =>
        EjecutarAsync<bool>("SP_CerrarSesionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_sesion_token", sesionToken);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<bool>> LiberarSesionAsync(long idUsuario, long idEjecutor, CancellationToken ct) =>
        EjecutarAsync<bool>("SP_LiberarSesionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_ejecutor", idEjecutor);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<bool>> AsignarAccesoAsync(
        long idUsuario, string? nombreUsuario, bool habilitar, long idEjecutor, CancellationToken ct) =>
        EjecutarAsync<bool>("SP_AsignarAccesoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_nombre_usuario", Valor(nombreUsuario));
                p.AddWithValue("p_habilitar",      Bit(habilitar));
                p.AddWithValue("p_id_ejecutor",    idEjecutor);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<AccesoMovilDto>> ObtenerAccesoAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<AccesoMovilDto>("SP_ObtenerAccesoMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new(3, "El procedimiento no devolvió datos.");

                return new(2, mensaje, new AccesoMovilDto(
                    EnteroLargo(r, "id_usuario"),
                    Texto(r, "nombre_usuario"),
                    Texto(r, "canal_acceso") ?? string.Empty,
                    Booleano(r, "habilitado"),
                    Texto(r, "sesion_equipo"),
                    FechaHora(r, "sesion_inicio"),
                    FechaHora(r, "sesion_expira")));
            }, ct);

    private static string? Recortar(string? valor, int largo)
    {
        if (valor is null) return null;
        var v = valor.Trim();
        return v.Length <= largo ? v : v[..largo];
    }
}
