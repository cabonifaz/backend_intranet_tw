using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class NotificacionesRepositorio(CadenaConexionBd conexion) : INotificacionesRepositorio
{
    public async Task<RespuestaDto<List<NotificacionDto>>> ObtenerPorUsuarioAsync(
        long idUsuario, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerNotificaciones", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_usuario", idUsuario);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<NotificacionDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<NotificacionDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var notificaciones = new List<NotificacionDto>();
            while (await reader.ReadAsync(ct))
            {
                notificaciones.Add(new NotificacionDto(
                    IdNotificacion: reader.GetInt32("id_notificacion"),
                    Tipo:           reader.GetString("tipo"),
                    Titulo:         reader.GetString("titulo"),
                    Cuerpo:         reader.GetString("cuerpo"),
                    TipoDot:        reader.GetString("tipo_dot"),
                    Tiempo:         reader.GetString("tiempo"),
                    Leida:          reader.GetInt32("leida") == 1,
                    CreadoEn:       reader.GetDateTime("creado_en")
                ));
            }

            return new RespuestaDto<List<NotificacionDto>>(2, mensaje, notificaciones);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<NotificacionDto>>(3, ex.Message);
        }
    }
}
