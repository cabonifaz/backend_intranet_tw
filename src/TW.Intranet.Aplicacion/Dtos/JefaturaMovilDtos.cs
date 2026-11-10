namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-28 / HU-31 — Menú de Jefatura y Centro de aprobaciones ────────────────────

/// <summary>
/// Resumen del día del menú de Jefatura (supervisores y administradores de cualquier área menos Servicio Técnico).
/// AreaCodigo: el área del usuario. Metrología se filtra por el área según la RQ; las demás áreas ven todos los servicios.
/// Los contadores de las tarjetas (desde AlertasCriticas) son NULL cuando no hay dato para este usuario (sin el permiso, el área no aplica
/// o no existe la fuente): la app no pinta contador. Ver SP_ObtenerMenuJefaturaMovil.
/// </summary>
public record MenuJefaturaMovilDto(
    string  AreaCodigo,
    string? AreaNombre,
    string? Sede,
    int     Programados,
    int     EnRuta,
    int     EnEjecucion,
    int     ConDemora,
    int     AprobacionesPendientes,
    int?    AlertasCriticas        = null,
    int?    InformesPorRevisar     = null,
    int?    CertificadosPendientes = null,
    int?    TicketsCorrelativo     = null,
    int?    MiEquipoTotal          = null,
    int?    MiEquipoEnLabores      = null,
    int?    AgendaConflictos       = null,
    int?    ViaticosPorRevisar     = null);

/// <summary>Bandeja única de lo que espera la decisión del jefe, con las urgentes primero.</summary>
public record AprobacionesMovilDto(
    int                        Total,
    int                        Urgentes,
    List<TipoAprobacionMovilDto> Tipos,
    List<AprobacionMovilDto>   Items);

/// <summary>Cantidad por tipo (salida | evidencia | ensayo | gasto). Hoy solo hay solicitudes de salida.</summary>
public record TipoAprobacionMovilDto(string Tipo, int Cantidad);

/// <summary>
/// Una solicitud en la bandeja. Tipo: salida. Id = id de la OS (la salida se resuelve por OS).
/// Urgente = el servicio es de hoy: el técnico está por salir.
/// </summary>
public record AprobacionMovilDto(
    string    Tipo,
    long      Id,
    string    Titulo,
    string    NumeroOs,
    string?   Tecnico,
    string?   Cliente,
    string?   Detalle,
    string?   FechaEjecucion,
    string?   HoraInicio,
    bool      Urgente,
    DateTime? SolicitadaEn);

/// <summary>Solicitud de salida con el checklist del técnico (sus pendientes y el motivo que dio).</summary>
public record AprobacionSalidaMovilDto(
    AutorizacionSalidaBandejaDto  Solicitud,
    List<ItemChecklistSalidaDto>  Items,
    List<string>                  Faltantes,
    string?                       AreaAutoriza);
