using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Notificaciones del usuario en la app móvil (App Mobile HU-02 / HU-04).</summary>
public interface INotificacionesMovilRepositorio
{
    Task<RespuestaDto<List<NotificacionMovilDto>>> ObtenerAsync(long idUsuario, CancellationToken ct);

    /// <summary>idNotificacion > 0 marca una; 0 marca todas las no leídas del usuario.</summary>
    Task<RespuestaDto<NotificacionesMarcadasDto>> MarcarLeidaAsync(long idUsuario, long idNotificacion, CancellationToken ct);
}
