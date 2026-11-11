using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface INotificacionesRepositorio
{
    /// <summary>Topbar actual (las 20 más recientes). Se mantiene sin cambios mientras el front migra a la campana nueva.</summary>
    Task<RespuestaDto<List<NotificacionDto>>> ObtenerPorUsuarioAsync(long idUsuario, CancellationToken ct);

    // ── HU-90 Centro de Notificaciones ────────────────────────────────────────
    Task<RespuestaDto<ResumenNotificacionesDto>> ObtenerResumenAsync(long idUsuario, CancellationToken ct);
    Task<RespuestaDto<BandejaNotificacionesDto>> ObtenerBandejaAsync(FiltrosBandejaNotificacionesDto filtros, long idUsuario, CancellationToken ct);
    /// <summary>Devuelve el detalle y la marca como leída.</summary>
    Task<RespuestaDto<DetalleNotificacionDto>> ObtenerDetalleAsync(long idNotificacion, long idUsuario, CancellationToken ct);
    /// <summary>ids = notificaciones a marcar (se ignoran si todas = true).</summary>
    Task<RespuestaDto<ResultadoMarcadoNotificacionesDto>> MarcarLeidasAsync(IReadOnlyCollection<long> ids, bool todas, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ResultadoArchivadoNotificacionDto>> ArchivarAsync(long idNotificacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ConteosFiltrosNotificacionesDto>> ObtenerConteosFiltrosAsync(long idUsuario, CancellationToken ct);

    /// <summary>Worker: guarda como notificación las alertas operativas activas del Módulo 11.</summary>
    Task<RespuestaDto<ResultadoAlertasOperativasDto>> GenerarAlertasOperativasAsync(CancellationToken ct);

    /// <summary>HU-90 parte 2 — Worker de tiempo real: notificaciones con id &gt; desdeId (desdeId &lt; 0 = solo el último id).</summary>
    Task<RespuestaDto<NotificacionesNuevasDto>> ObtenerNuevasAsync(long desdeId, int limite, CancellationToken ct);
}
