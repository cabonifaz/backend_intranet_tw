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

/// <summary>Cantidad por tipo (salida | llegada | evidencia | ensayo | gasto).</summary>
public record TipoAprobacionMovilDto(string Tipo, int Cantidad);

/// <summary>
/// Una solicitud en la bandeja. Tipo: salida | llegada (Id = id de la OS: se resuelven por OS) | evidencia (Id = id_evidencia) |
/// ensayo (Id = id_informe) | gasto (Id = id_gasto). Urgente = el servicio es de hoy (el ensayo con error, siempre).
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

/// <summary>
/// Detalle de una evidencia forzada, un ensayo con error o un gasto para el jefe (HU-31). Las columnas que no aplican al tipo van en null.
/// Estado: evidencia/ensayo pendiente | aprobada | rechazada · gasto pendiente | observado | aprobado | rechazado.
/// </summary>
public record CabeceraAprobacionMovilDto(
    string Tipo, long Id, string Titulo, string Estado, long IdOs, string NumeroOs, string? Cliente, string? Sede, string? Tecnico,
    string? FechaEjecucion, string? HoraInicio, DateTime? SolicitadaEn, string? Motivo, string? Detalle, string? Comentario,
    string? ResueltoPor, DateTime? ResueltoEn, bool PuedeResolver,
    // evidencia
    string? CodigoEvidencia, string? MotivoRechazoIa, bool? EsVideo,
    // ensayo
    string? Equipo, int? NCriticas,
    // gasto
    string? Codigo, string? Origen, string? Concepto, decimal? Monto, string? FechaGasto, string? Descripcion, string? MotivoSinFoto,
    decimal? MontoIa, bool? CoincideIa, string? CodigoProgramacion);

/// <summary>Lectura de un ensayo que quedó fuera del EMP.</summary>
public record LecturaEnsayoMovilDto(string? Tipo, string? Punto, decimal? Carga, decimal? Lectura, decimal? Error, decimal? Tolerancia);

/// <summary>Foto de la aprobación. Evidencia: GET …/evidencias/{id}/archivo[?cuadro=true] · gasto: GET …/gastos/{id}/fotos/{orden}.</summary>
public record FotoAprobacionMovilDto(int Orden, bool EsVideo, bool TieneCuadro);

public record DetalleAprobacionMovilDto(
    CabeceraAprobacionMovilDto Cabecera, List<RepartoGastoMovilDto> Reparto, List<LecturaEnsayoMovilDto> Lecturas, List<FotoAprobacionMovilDto> Fotos);

/// <summary>Archivo de una aprobación (ruta del almacenamiento). EsVideo: el archivo principal es MP4.</summary>
public record ArchivoAprobacionMovilDto(string Ruta, string? RutaCuadro, bool EsVideo);

/// <summary>Solicitud de salida con el checklist del técnico (sus pendientes y el motivo que dio).</summary>
public record AprobacionSalidaMovilDto(
    AutorizacionSalidaBandejaDto  Solicitud,
    List<ItemChecklistSalidaDto>  Items,
    List<string>                  Faltantes,
    string?                       AreaAutoriza);
