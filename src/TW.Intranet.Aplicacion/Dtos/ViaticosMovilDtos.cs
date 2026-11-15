namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-25 / HU-26 — Viáticos y gastos del técnico (lectura) ──────────────────────

/// <summary>Viáticos asignados al técnico al programar el servicio y los gastos que rindió.</summary>
public record ViaticosMovilDto(
    ResumenViaticosMovilDto        Resumen,
    List<ViaticoMovilDto>          Viaticos,
    List<LineaViaticoMovilDto>     Lineas,
    List<GastoMovilDto>            Gastos,
    List<RepartoGastoMovilDto>?    Repartos = null,
    List<FotoGastoMovilDto>?       Fotos    = null);

/// <summary>Una parte de un gasto rendido contra una línea del adelanto (HU-27).</summary>
public record RepartoGastoMovilDto(long IdGasto, long IdViaticoLinea, string Concepto, decimal Monto);

/// <summary>Foto de un gasto. Orden = n de GET api/movil/viaticos/gastos/{idGasto}/fotos/{n} y de fotosConservar al corregir.</summary>
public record FotoGastoMovilDto(long IdGasto, int Orden);

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

/// <summary>
/// Adelanto de un concepto dentro de un viático. EstadoDeposito: depositado | pendiente.
/// IdViaticoLinea: la línea a usar en el reparto al rendir un gasto (HU-27). Rendido = lo repartido en ella + gastos antiguos del mismo concepto.
/// </summary>
public record LineaViaticoMovilDto(
    long      IdProgramacion,
    int       IdConcepto,
    string    Concepto,
    decimal   Asignado,
    decimal   Depositado,
    string?   FechaDeposito,
    decimal   Rendido,
    decimal   PorRendir,
    string    EstadoDeposito,
    long      IdViaticoLinea = 0);

/// <summary>
/// Gasto rendido por el técnico. Estado: pendiente | aprobado | observado | rechazado.
/// Origen: viatico | reembolso (null = gasto anterior a HU-27). ConceptoTexto: el texto de "Otro". MontoIa / CoincideIa: lectura de la boleta con IA.
/// </summary>
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
    string?   CodigoProgramacion,
    string?   Origen        = null,
    string?   ConceptoTexto = null,
    string?   MotivoSinFoto = null,
    decimal?  MontoIa       = null,
    bool?     CoincideIa    = null,
    int       NFotos        = 0);

/// <summary>Concepto del catálogo CONCEPTO_GASTO para un reembolso. EsOtro: la app pide el texto del concepto.</summary>
public record ConceptoGastoMovilDto(int IdConcepto, string Concepto, bool EsOtro);

// ── App Mobile HU-27 — Rendir un gasto o corregir uno observado ────────────────────────────

/// <summary>Línea del reparto: de qué viático (línea del adelanto) sale cuánto.</summary>
public class RepartoGastoEntradaDto
{
    public long    IdViaticoLinea { get; set; }
    public decimal Monto          { get; set; }
}

/// <summary>
/// Campo "datos" (JSON) del multipart de POST/PUT api/movil/viaticos/gastos. Origen: viatico (trae Reparto) | reembolso (trae IdConcepto y,
/// si es "Otro", ConceptoTexto). IdCliente: GUID de la app para que un reintento no duplique el gasto. FechaGasto: "yyyy-MM-dd".
/// FotosConservar (solo al corregir): orden de las fotos que se quedan.
/// </summary>
public class PeticionGastoMovilDto
{
    public string?                       IdCliente      { get; set; }
    public string?                       Origen         { get; set; }
    public long?                         IdOs           { get; set; }
    public int?                          IdConcepto     { get; set; }
    public string?                       ConceptoTexto  { get; set; }
    public decimal?                      Monto          { get; set; }
    public string?                       FechaGasto     { get; set; }
    public string?                       Descripcion    { get; set; }
    public List<RepartoGastoEntradaDto>? Reparto        { get; set; }
    public string?                       MotivoSinFoto  { get; set; }
    public List<int>?                    FotosConservar { get; set; }
}

/// <summary>Datos ya validados para el SP.</summary>
public record ComandoGastoMovil(
    long IdGasto, string? IdCliente, string Origen, long IdOs, int? IdConcepto, string? ConceptoTexto, decimal Monto, DateOnly FechaGasto,
    string? Descripcion, string? RepartoJson, string? MotivoSinFoto, IReadOnlyList<string> FotosNuevas, string? FotosConservarJson,
    decimal? MontoIa, bool? CoincideIa);

/// <summary>Resultado de rendir/corregir. Duplicado = el GUID ya existía (reintento). Advertencias: líneas del reparto que se pasan de lo que les queda.</summary>
public record ResultadoGastoMovilDto(
    long IdGasto, string Codigo, string Estado, bool Duplicado, List<string> Advertencias, decimal? MontoIa = null, bool? CoincideIa = null);
