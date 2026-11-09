namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-45 Asignación de Viáticos y Rendición de Gastos Operativos (Sprint 5) ───────────────────────────────

public record ViaticosCabeceraDto(
    long IdProgramacion, string Codigo, string Estado, string EstadoLabel, long IdOs, string NumeroOs, string Tipo, string? RazonSocial,
    string? FechaEjecucion, string? HoraInicio, string? HoraFin, long? IdTecnicoPrincipal, string? TecnicoPrincipal, string? CargoPrincipal,
    bool PuedeGestionar, string? MotivoNoGestionar, bool RendicionCerrada, string Version, string Moneda);

public record ViaticosTecnicoDto(
    long IdUsuario, string Nombre, string? Cargo, string Rol, bool Vigente, decimal SubtotalAsignado, decimal RendidoAprobado);

public record ConceptoGastoDto(int IdConcepto, string Nombre, string Categoria, bool Personalizado);

/// <summary>Línea de la pestaña 1. EstadoDeposito: pendiente | depositado (lo marca Contabilidad fuera de este módulo).</summary>
public record LineaAsignacionDto(
    long IdGasto, long IdTecnico, string Tecnico, string Rol, int IdConcepto, string Concepto, decimal Monto, string EstadoDeposito,
    string? FechaDeposito, bool Notificado, bool Editable);

public record TotalesAsignacionDto(
    decimal TotalAsignado, decimal TotalDepositado, decimal TotalPendiente, decimal PendientePorNotificar, int LineasPorNotificar);

/// <summary>Gasto presentado desde la app móvil (pestaña 2). Estado: pendiente | aprobado | observado | rechazado.</summary>
public record GastoRendidoDto(
    long IdGasto, string? Fecha, long IdTecnico, string Tecnico, int IdConcepto, string Concepto, string? Descripcion, decimal Monto,
    bool TieneComprobante, string Estado, string? ComentarioRevision, bool PuedeAprobar, bool PuedeObservar, bool PuedeRechazar);

/// <summary>Tarjetas de la pestaña 2. TipoSaldo: a_favor_tecnico (reembolso adicional) | a_devolver (devolución del técnico) | cuadrado.</summary>
public record ResumenRendicionDto(
    long IdProgramacion, decimal TotalAsignado, decimal TotalDepositado, decimal TotalPendienteDeposito, decimal TotalSolicitado, int NGastos,
    int NComprobantes, decimal TotalAprobado, int NAprobados, decimal TotalObservado, decimal TotalPendiente, decimal TotalRechazado,
    decimal SaldoVsAsignado, string TipoSaldo, int PendientesRevision, bool Cerrada, bool PuedeCerrar, string? MotivoNoCerrar, string? AdvertenciaCierre);

public record CierreRendicionDto(
    string? CerradoEn, string? CerradoPor, decimal TotalAsignado, decimal TotalAprobado, decimal Saldo, string TipoSaldo);

public record ViaticosProgramacionDto(
    ViaticosCabeceraDto Cabecera, IReadOnlyList<ViaticosTecnicoDto> Tecnicos, IReadOnlyList<ConceptoGastoDto> Conceptos,
    IReadOnlyList<LineaAsignacionDto> Lineas, TotalesAsignacionDto Totales, IReadOnlyList<GastoRendidoDto> Gastos,
    ResumenRendicionDto Resumen, CierreRendicionDto? Cierre);

// ── Entradas ──

/// <summary>Línea de la asignación. IdGasto null = nueva. Concepto: IdConcepto del catálogo O NuevoConcepto (no ambos).</summary>
public class LineaViaticoDto
{
    public long?    IdGasto       { get; set; }
    public long     IdTecnico     { get; set; }
    public int?     IdConcepto    { get; set; }
    public string?  NuevoConcepto { get; set; }
    public decimal  Monto         { get; set; }
}

/// <summary>Guardar la asignación COMPLETA que debe quedar. Version = la huella devuelta por el GET (concurrencia optimista).</summary>
public class GuardarViaticosDto
{
    public string?                 Version { get; set; }
    public List<LineaViaticoDto>?  Lineas  { get; set; }
}

public class RevisarGastoDto
{
    public string? Accion     { get; set; }   // aprobar | observar | rechazar
    public string? Comentario { get; set; }   // obligatorio al observar o rechazar
}

public record GuardarViaticosNormalizado(string Version, string LineasJson);

public record GuardarViaticosResultadoDto(
    long IdProgramacion, int Creadas, int Modificadas, int Retiradas, decimal TotalAsignado, decimal TotalDepositado, decimal TotalPendiente,
    int NotificadosContabilidad, bool SinCambios, int ConceptosNuevos, string Version);

public record RevisarGastoResultadoDto(long IdProgramacion, long IdGasto, string Estado, long IdTecnico, ResumenRendicionDto Resumen);

public record CerrarRendicionResultadoDto(
    long IdProgramacion, decimal TotalAsignado, decimal TotalDepositado, decimal TotalSolicitado, decimal TotalAprobado, decimal TotalRechazado,
    decimal Saldo, string TipoSaldo, int NotificadosContabilidad);

public record ComprobanteGastoDto(
    long IdGasto, string Url, decimal Monto, string Estado, string? Fecha, string Concepto, string Tecnico);
