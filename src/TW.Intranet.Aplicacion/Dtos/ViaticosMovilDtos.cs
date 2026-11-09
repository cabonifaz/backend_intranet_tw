namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-25 / HU-26 — Viáticos y gastos del técnico (lectura) ──────────────────────

/// <summary>Viáticos asignados al técnico al programar el servicio y los gastos que rindió.</summary>
public record ViaticosMovilDto(
    ResumenViaticosMovilDto        Resumen,
    List<ViaticoMovilDto>          Viaticos,
    List<LineaViaticoMovilDto>     Lineas,
    List<GastoMovilDto>            Gastos);

/// <summary>Encabezado de "Viáticos y Gastos" (y del menú): saldo por rendir y gastos en revisión.</summary>
public record ResumenViaticosMovilDto(
    decimal SaldoPorRendir,
    int     ViaticosActivos,
    int     ViaticosFinalizados,
    decimal GastosEnRevision,
    int     GastosEnRevisionCantidad,
    int     GastosObservadosCantidad);

/// <summary>
/// Un viático = el adelanto de una programación para este técnico. Cerrado = la rendición ya se cerró (finalizado).
/// TipoSaldo (solo cerrado): reembolso | devolucion | cuadrado.
/// </summary>
public record ViaticoMovilDto(
    long      IdProgramacion,
    string    Codigo,
    string    EstadoProgramacion,
    string    EstadoProgramacionLabel,
    bool      Cerrado,
    long      IdOs,
    string    NumeroOs,
    string?   Cliente,
    string?   Sede,
    string?   FechaEjecucion,
    string?   HoraInicio,
    string?   HoraFin,
    decimal   Asignado,
    decimal   Depositado,
    decimal   PendienteDeposito,
    decimal   Rendido,
    decimal   PorRendir,
    int       PorcentajeRendido,
    DateTime? CerradoEn,
    decimal?  SaldoFinal,
    string?   TipoSaldo);

/// <summary>Adelanto de un concepto dentro de un viático. EstadoDeposito: depositado | pendiente.</summary>
public record LineaViaticoMovilDto(
    long      IdProgramacion,
    int       IdConcepto,
    string    Concepto,
    decimal   Asignado,
    decimal   Depositado,
    string?   FechaDeposito,
    decimal   Rendido,
    decimal   PorRendir,
    string    EstadoDeposito);

/// <summary>Gasto rendido por el técnico. Estado: pendiente | aprobado | observado | rechazado.</summary>
public record GastoMovilDto(
    long      IdGasto,
    string    Codigo,
    string?   Fecha,
    int       IdConcepto,
    string    Concepto,
    decimal   Monto,
    string    Moneda,
    string?   Descripcion,
    string    Estado,
    string?   ComentarioRevision,
    string?   RevisadoPor,
    DateTime? RevisadoEn,
    DateTime? CreadoEn,
    bool      TieneComprobante,
    long      IdOs,
    string    NumeroOs,
    long?     IdProgramacion,
    string?   CodigoProgramacion);
