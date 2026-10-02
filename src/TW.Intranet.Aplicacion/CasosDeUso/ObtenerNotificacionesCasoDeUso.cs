using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerNotificacionesCasoDeUso(INotificacionesRepositorio repositorio)
{
    public async Task<RespuestaDto<List<NotificacionDto>>> EjecutarAsync(
        long idUsuario, CancellationToken ct = default)
        => await repositorio.ObtenerPorUsuarioAsync(idUsuario, ct);
}
