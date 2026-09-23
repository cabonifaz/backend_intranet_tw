using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface INotificacionesRepositorio
{
    Task<RespuestaDto<List<NotificacionDto>>> ObtenerPorUsuarioAsync(long idUsuario, CancellationToken ct);
}
