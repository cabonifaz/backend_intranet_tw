namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-02 / HU-04 — Notificaciones ───────────────────────────────────────────────

/// <summary>
/// Un aviso del usuario. Tipo: autorizacion_aprobada | autorizacion_rechazada | autorizacion_solicitud | solicitud_enviada |
/// gasto_aprobado | gasto_observado | gasto_rechazado | servicio | demora | general (lo clasifica SP_ObtenerNotificacionesMovil).
/// EntidadTipo/IdEntidad dicen a qué abre la app ("orden_servicio" = el detalle de ese servicio).
/// PendientesAprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
/// </summary>
public record NotificacionMovilDto(
    long      IdNotificacion,
    string    Tipo,
    string    Titulo,
    string    Cuerpo,
    string?   EntidadTipo,
    long?     IdEntidad,
    bool      Leida,
    DateTime? Fecha,
    string?   PendientesAprobados);

/// <summary>Cuántas notificaciones se marcaron como leídas.</summary>
public record NotificacionesMarcadasDto(int Marcadas);
