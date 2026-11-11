using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Notificaciones del usuario en la app móvil (App Mobile HU-02 / HU-04).</summary>
public class NotificacionesMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), INotificacionesMovilRepositorio
{
    public Task<RespuestaDto<List<NotificacionMovilDto>>> ObtenerAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<List<NotificacionMovilDto>>("SP_ObtenerNotificacionesMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                var lista = new List<NotificacionMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new NotificacionMovilDto(
                        EnteroLargo(r, "id_notificacion"),
                        Texto(r, "tipo") ?? "general",
                        Texto(r, "titulo") ?? string.Empty,
                        Texto(r, "cuerpo") ?? string.Empty,
                        Texto(r, "entidad_tipo"),
                        EnteroLargoNulo(r, "id_entidad"),
                        Booleano(r, "leida"),
                        FechaHora(r, "fecha_creacion"),
                        Texto(r, "pendientes_aprobados"),
                        Texto(r, "prioridad"),
                        Booleano(r, "critica")));
                return new RespuestaDto<List<NotificacionMovilDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<NotificacionesMarcadasDto>> MarcarLeidaAsync(long idUsuario, long idNotificacion, CancellationToken ct) =>
        EjecutarAsync<NotificacionesMarcadasDto>("SP_MarcarNotificacionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_notificacion", idNotificacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var marcadas = await r.ReadAsync(ct) ? Entero(r, "marcadas") : 0;
                return new RespuestaDto<NotificacionesMarcadasDto>(2, mensaje, new NotificacionesMarcadasDto(marcadas));
            }, ct);
}
