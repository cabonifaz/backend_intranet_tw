using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Dominio.Entidades;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class AutenticacionRepositorio(CadenaConexionBd conexion) : IAutenticacionRepositorio
{
    public async Task<RespuestaDto<Usuario>> ObtenerPorCorreoAsync(
        string correo, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerUsuarioPorCorreo", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_correo", correo);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<Usuario>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<Usuario>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<Usuario>(3, "El procedimiento no devolvió datos del usuario.");

            var usuario = new Usuario
            {
                IdUsuario    = reader.GetInt64("id_usuario"),
                Nombre       = reader.GetString("nombre"),
                Apellido     = reader.GetString("apellido"),
                Correo       = reader.GetString("correo"),
                PasswordHash = reader.GetString("password_hash"),
                RolSistema   = reader.GetString("rol_sistema"),
                CanalAcceso  = reader.GetString("canal_acceso"),
                Estado       = reader.GetString("estado"),
            };

            return new RespuestaDto<Usuario>(2, mensaje, usuario);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<Usuario>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<string>> ActualizarUltimoLoginAsync(
        long idUsuario, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ActualizarUltimoLogin", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_usuario", idUsuario);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<string>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<string>(idTipo, mensaje);

            await reader.NextResultAsync(ct);
            string sesionToken = string.Empty;
            if (await reader.ReadAsync(ct))
                sesionToken = reader.GetString("sesion_token");

            return new RespuestaDto<string>(2, mensaje, sesionToken);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<string>(3, ex.Message);
        }
    }

    public async Task<bool> VerificarSesionTokenAsync(
        long idUsuario, string sesionToken, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_VerificarSesionToken", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_usuario",   idUsuario);
            cmd.Parameters.AddWithValue("p_sesion_token", sesionToken);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct)) return false;

            return reader.GetInt32("IdTipoMensaje") == 2;
        }
        catch
        {
            return false;
        }
    }
}
