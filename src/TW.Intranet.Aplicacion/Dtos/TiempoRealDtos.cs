namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-90 parte 2 — Tiempo real (SignalR, hub /hubs/notificaciones) ──────────────────────────────────────────────

/// <summary>Nombres de los eventos (contrato con el front: connection.on("notificacion.creada", e => …)).</summary>
public static class EventosTiempoReal
{
    public const string NotificacionCreada      = "notificacion.creada";
    public const string NotificacionActualizada = "notificacion.actualizada";
    public const string OcRegistrada            = "oc.registrada";
    public const string OcAnulada               = "oc.anulada";
    public const string VbAsignado              = "vb.asignado";
    public const string VbResuelto              = "vb.resuelto";
    public const string OsEmitida               = "os.emitida";
    public const string OsEstadoCambiado        = "os.estado_cambiado";
    public const string PrecotizacionRecibida   = "precotizacion.recibida";
}

/// <summary>
/// Grupos de SignalR. Al conectarse, cada usuario entra a user_{id}, rol_{rol} y permiso_{accion} por cada acción de
/// <see cref="AccionesConGrupo"/> que tenga permitida. Los grupos de entidad (oc_{id}, os_{id}, propuesta_{id}) los pide el
/// front con SuscribirEntidad y el hub valida el permiso de ver ese módulo.
/// </summary>
public static class GruposTiempoReal
{
    /// <summary>Acciones (tabla_maestra 88) que dan un grupo permiso_{accion}: las bandejas que se refrescan con eventos de dominio.</summary>
    public static readonly IReadOnlyList<string> AccionesConGrupo =
        ["oc_bandeja", "propuesta_vb_bandeja", "os_bandeja", "os_bandeja_operaciones", "precot_ver"];

    /// <summary>Entidades a las que el front se puede suscribir y las acciones que permiten verlas (basta una).</summary>
    public static readonly IReadOnlyDictionary<string, string[]> EntidadesSuscribibles = new Dictionary<string, string[]>
    {
        ["oc"]        = ["oc_bandeja"],
        ["os"]        = ["os_bandeja", "os_bandeja_operaciones"],
        ["propuesta"] = ["propuesta_ver", "propuesta_vb_bandeja"],
    };

    public static string Usuario(long idUsuario)            => $"user_{idUsuario}";
    public static string Rol(string rol)                    => $"rol_{Normalizar(rol)}";
    public static string Permiso(string accion)             => $"permiso_{accion}";
    public static string Entidad(string tipo, long id)      => $"{tipo}_{id}";

    /// <summary>"Jefe Comercial" → "jefe_comercial" (solo a-z, 0-9 y _).</summary>
    public static string Normalizar(string texto)
    {
        var limpio = new string(texto.Trim().ToLowerInvariant().Select(c => char.IsAsciiLetterOrDigit(c) ? c : '_').ToArray());
        return limpio.Length > 40 ? limpio[..40] : limpio;
    }
}

/// <summary>Sobre común de todos los eventos: { evento, fecha (hora de Lima), datos }.</summary>
public record EventoTiempoRealDto(string Evento, DateTime Fecha, object Datos);

/// <summary>notificacion.creada → user_{destinatario}. Misma fila que la bandeja + contador absoluto del badge.</summary>
public record NotificacionCreadaEventoDto(FilaNotificacionDto Notificacion, int NoLeidas);

/// <summary>notificacion.actualizada → user_{id}: sincroniza otras pestañas. estado: leida | archivada. Todas = "marcar todas".</summary>
public record NotificacionActualizadaEventoDto(List<long> Ids, bool Todas, string Estado, int NoLeidas);

/// <summary>oc.registrada / oc.anulada → permiso_oc_bandeja + oc_{idOc} + propuesta_{id} de cada propuesta vinculada.</summary>
public record OcEventoDto(long IdOc, string NumeroOc, string Estado, List<long> IdsPropuesta, bool Autogenerada);

/// <summary>vb.asignado / vb.resuelto → permiso_propuesta_vb_bandeja + propuesta_{idPropuesta}. accion: aprobar | corregir (solo en vb.resuelto).</summary>
public record VbEventoDto(long IdPropuesta, string? Numero, string Estado, string? EstadoVb, string? Accion);

/// <summary>os.emitida / os.estado_cambiado → permiso_os_bandeja + permiso_os_bandeja_operaciones + os_{idOs}.</summary>
public record OsEventoDto(long IdOs, string Numero, string? Tipo, string Estado, bool Reemitida);

/// <summary>precotizacion.recibida → permiso_precot_ver.</summary>
public record PrecotizacionEventoDto(long IdPrecotizacion, string Numero, string Estado, long IdInforme);

/// <summary>Notificación nueva detectada por el worker de tiempo real (una fila por destinatario).</summary>
public record NotificacionNuevaDto(long IdUsuarioDestino, FilaNotificacionDto Fila, int NoLeidas);

/// <summary>UltimoId = MAX(id_notificacion) en el momento de la consulta.</summary>
public record NotificacionesNuevasDto(long UltimoId, List<NotificacionNuevaDto> Nuevas);
