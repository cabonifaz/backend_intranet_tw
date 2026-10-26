namespace TW.Intranet.Aplicacion.Dtos;

// ═══════════════════════════════════════════════════════════════════════════
// Módulo Órdenes de Servicio / Metrología (OS / OM), Sprint 4 (HU-40 a HU-44).
// La OS/OM no maneja montos: es el documento operativo que nace de una propuesta aceptada.
// ═══════════════════════════════════════════════════════════════════════════

// ── HU-41 Bandeja ──────────────────────────────────────────────────────────

/// <summary>Filtros de la bandeja (query string).</summary>
public class FiltrosBandejaOrdenesServicioDto
{
    /// <summary>todas (defecto), borrador, emitida, programada, en_ejecucion, finalizada, anulada (la tarjeta pulsada).</summary>
    public string?   Estado        { get; set; }
    /// <summary>todos (defecto), OS u OM.</summary>
    public string?   Tipo          { get; set; }
    public long?     IdCliente     { get; set; }
    /// <summary>Responsable comercial de la orden.</summary>
    public long?     IdResponsable { get; set; }
    /// <summary>Fecha de emisión (los borradores usan su fecha de creación).</summary>
    public DateTime? FechaDesde    { get; set; }
    public DateTime? FechaHasta    { get; set; }
    /// <summary>N° OS/OM, N° de propuesta, cliente o RUC.</summary>
    public string?   Busqueda      { get; set; }
    public int       Pagina        { get; set; } = 1;
    public int       PorPagina     { get; set; } = 10;
}

/// <summary>Tarjetas KPI (con todos los filtros salvo el estado). Cada tarjeta filtra por su estado.</summary>
public record TarjetasOrdenesServicioDto(
    int Total,
    int Borradores,
    int Emitidas,
    /// <summary>Órdenes emitidas desde el lunes de esta semana ("+5 esta semana").</summary>
    int EmitidasSemana,
    int Programadas,
    int EnEjecucion,
    int Finalizadas,
    /// <summary>Finalizadas este mes.</summary>
    int FinalizadasMes,
    int Anuladas);

/// <summary>Fila de la bandeja.</summary>
public record ItemBandejaOrdenServicioDto
{
    public long      IdOs                   { get; init; }
    /// <summary>OS u OM.</summary>
    public string    Tipo                   { get; init; } = "OS";
    public string    Numero                 { get; init; } = "";
    /// <summary>Estado detallado: borrador, emitida, programada, reprogramada, en_ruta, en_ejecucion, pausada, bloqueada, finalizada, anulada.</summary>
    public string    Estado                 { get; init; } = "";
    /// <summary>Grupo de la tarjeta: borrador, emitida, programada, en_ejecucion, finalizada, anulada (color del chip).</summary>
    public string    EstadoGrupo            { get; init; } = "";
    public string    EstadoLabel            { get; init; } = "";
    /// <summary>Fecha de emisión; en un borrador (Emitida = false), su fecha de creación.</summary>
    public DateTime? FechaEmision           { get; init; }
    /// <summary>false = la orden no tiene fecha de emisión registrada (borrador u orden anterior al módulo).</summary>
    public bool      Emitida                { get; init; }
    public long?     IdCliente              { get; init; }
    public string?   RazonSocial            { get; init; }
    public string?   Ruc                    { get; init; }
    public long?     IdPropuesta            { get; init; }
    public string?   NumeroPropuesta        { get; init; }
    public int?      VersionPropuesta       { get; init; }
    /// <summary>Para los modales reutilizables de Documentos (HU-31) e Historial de Auditoría (HU-32).</summary>
    public long?     IdExpediente           { get; init; }
    public long?     IdResponsable          { get; init; }
    public string?   Responsable            { get; init; }
    public int       NumeroEquipos          { get; init; }
    public int       NumeroConceptos        { get; init; }
    /// <summary>Hay una solicitud de edición esperando al Jefe Comercial.</summary>
    public bool      SolicitudPendiente     { get; init; }
    public long?     IdSolicitudPendiente   { get; init; }
    /// <summary>El usuario tiene una solicitud de edición aprobada pendiente de ejecutar.</summary>
    public bool      EdicionAprobada        { get; init; }
    // Acciones del menú ⋯ según estado y rol
    public bool      PuedeEditar            { get; init; }
    public bool      PuedeSolicitarEdicion  { get; init; }
    public bool      PuedeResolverSolicitud { get; init; }
    public bool      PuedeAnular            { get; init; }
}

public record BandejaOrdenesServicioDto(
    TarjetasOrdenesServicioDto        Tarjetas,
    List<ItemBandejaOrdenServicioDto> Items,
    int                               Total,
    int                               Pagina,
    int                               PorPagina,
    List<OpcionFiltroDto>             Clientes,
    List<OpcionFiltroDto>             Responsables);
