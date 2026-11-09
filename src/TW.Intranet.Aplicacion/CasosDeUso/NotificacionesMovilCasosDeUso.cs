using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-02 / HU-04 — Notificaciones ───────────────────────────────────────────────

/// <summary>Avisos del usuario que inició sesión (sale del token: nadie puede pedir los de otro).</summary>
public class ObtenerNotificacionesMovilCasoDeUso(INotificacionesMovilRepositorio repositorio)
{
    public Task<RespuestaDto<List<NotificacionMovilDto>>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<List<NotificacionMovilDto>>(1, "No se pudo identificar al usuario."));

        return repositorio.ObtenerAsync(idUsuario, ct);
    }
}

/// <summary>Marca una notificación (o todas) como leída. Solo las del propio usuario: el SP no toca las de otros.</summary>
public class MarcarNotificacionMovilCasoDeUso(INotificacionesMovilRepositorio repositorio)
{
    /// <summary>idNotificacion = 0 marca todas las no leídas.</summary>
    public Task<RespuestaDto<NotificacionesMarcadasDto>> EjecutarAsync(long idUsuario, long idNotificacion, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<NotificacionesMarcadasDto>(1, "No se pudo identificar al usuario."));
        if (idNotificacion < 0)
            return Task.FromResult(new RespuestaDto<NotificacionesMarcadasDto>(1, "Notificación no encontrada."));

        return repositorio.MarcarLeidaAsync(idUsuario, idNotificacion, ct);
    }
}
