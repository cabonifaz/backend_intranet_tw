namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-52 / HU-57 (Sprint 5) Aprobaciones y viáticos de una OS: Seguimiento (durante) y Revisión de Informes (después) ─────────

/// <summary>
/// Una aprobación de la OS. Tipo: salida | llegada | evidencia | ensayo. Estado: pendiente | aprobada | rechazada.
/// PuedeResolver: el usuario es el encargado del área (o supervisión general / administrador) y la solicitud sigue pendiente.
/// </summary>
public record AprobacionServicioDto(
    string Tipo, long Id, string? Titulo, string? Solicitante, DateTime? SolicitadoEn, string? Motivo, string? Detalle, string Estado,
    string? ResueltoPor, string? Cargo, DateTime? ResueltoEn, string? Comentario, bool Urgente, bool PuedeResolver);

public record TotalesAprobacionesDto(int Total, int Pendientes, int Aprobadas, int Rechazadas);

public record AprobacionesServicioDto(IReadOnlyList<AprobacionServicioDto> Aprobaciones, TotalesAprobacionesDto Totales);

/// <summary>Body de PUT …/aprobaciones/{tipo}/{id}: aprobar (true) o rechazar (false) con comentario obligatorio (1 a 500 caracteres).</summary>
public class ResolverAprobacionServicioDto
{
    public bool?   Aprobar    { get; set; }
    public string? Comentario { get; set; }
}

/// <summary>PuedeRevisar / PuedeGestionar: solo el Jefe de Operaciones; desde la Revisión de Informes siempre false (solo lectura).</summary>
public record ViaticosOsCabeceraDto(
    long? IdProgramacion, string? Codigo, string? Estado, bool PuedeRevisar, bool PuedeGestionar, bool RendicionCerrada, string Moneda);

/// <summary>TipoSaldo: reembolso (a favor del técnico) | devolucion (el técnico devuelve) | cuadrado.</summary>
public record ViaticosOsResumenDto(
    decimal Asignado, decimal Depositado, decimal PendienteDeposito, decimal Rendido, decimal Aprobado, decimal Rechazado,
    decimal PorRevisar, int NPorRevisar, decimal PorRendir, decimal Saldo, string TipoSaldo);

/// <summary>Línea de la asignación por técnico y concepto. EstadoDeposito: pendiente | depositado.</summary>
public record ViaticoLineaOsDto(
    long IdGasto, long IdTecnico, string Tecnico, string Rol, int IdConcepto, string Concepto, decimal Asignado, decimal Rendido,
    decimal PorRendir, string EstadoDeposito, string? FechaDeposito);

/// <summary>
/// Gasto rendido por el técnico. Estado: pendiente | observado | aprobado | rechazado. NFotos: fotos del comprobante (1 a 5).
/// Origen: viatico (sale del adelanto, ver Repartos) | reembolso (lo pagó el técnico) | null (gasto anterior a la rendición desde la app).
/// MontoIa / CoincideIa: total que leyó la IA en la boleta y si coincide con el monto (null = sin lectura).
/// </summary>
public record GastoRendidoOsDto(
    long IdGasto, string? Fecha, long IdTecnico, string Tecnico, int IdConcepto, string Concepto, string? Descripcion, decimal Monto,
    string Estado, string? ComentarioRevision, string? RevisadoPor, DateTime? RevisadoEn, int NFotos, string? MotivoSinFoto,
    decimal? MontoIa, bool? CoincideIa, bool PuedeRevisar, string? Origen = null);

/// <summary>Parte de un gasto rendido contra una línea del adelanto.</summary>
public record RepartoGastoOsDto(long IdGasto, long IdViaticoLinea, string Concepto, decimal Monto);

/// <summary>Cierre de la rendición. Estado: abierta | cerrada | sin_programacion. Tipo: reembolso | devolucion | cuadrado.</summary>
public record CierreRendicionOsDto(
    string Estado, decimal Asignado, decimal Aprobado, decimal Rechazado, decimal Saldo, string Tipo, string? CerradoPor, DateTime? CerradoEn);

/// <summary>Viáticos de la OS. Cierre: solo desde la Revisión de Informes (HU-57).</summary>
public record ViaticosOsDto(
    ViaticosOsCabeceraDto Cabecera, ViaticosOsResumenDto Resumen, IReadOnlyList<ViaticoLineaOsDto> Lineas, IReadOnlyList<GastoRendidoOsDto> Gastos,
    CierreRendicionOsDto? Cierre, IReadOnlyList<RepartoGastoOsDto>? Repartos = null);
