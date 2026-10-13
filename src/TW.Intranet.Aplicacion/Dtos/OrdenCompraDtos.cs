namespace TW.Intranet.Aplicacion.Dtos;

// ══════════════════════ HU-22 — Registro de Orden de Compra recibida ══════════════════════

/// <summary>Propuesta aceptada a la que se vincula la OC (base del indicador de cobertura).</summary>
public record PropuestaOrdenCompraDto
{
    public long      IdPropuesta         { get; init; }
    public string    Numero              { get; init; } = "";
    public int       Version             { get; init; }
    public long      IdCliente           { get; init; }
    public string    RazonSocial         { get; init; } = "";
    public string?   Ruc                 { get; init; }
    public long?     IdRequerimiento     { get; init; }
    public string?   NumeroRq            { get; init; }
    /// <summary>Monto de la propuesta aprobada (se compara con el monto de la OC).</summary>
    public decimal   Total               { get; init; }
    public int       IdMoneda            { get; init; }
    public string?   Moneda              { get; init; }
    public string?   MonedaSimbolo       { get; init; }
    public string?   MonedaNombre        { get; init; }
    public DateTime? FechaAceptacion     { get; init; }
    public string?   TipoAceptacion      { get; init; }
    public long      IdResponsable       { get; init; }
    public string?   Responsable         { get; init; }
    public DateTime? FechaServidor       { get; init; }
    public int       VigenciaDiasDefecto { get; init; }
}

public record MonedaOrdenCompraDto(int Id, string Nombre, string? Simbolo, string? Codigo);

public record PreparacionOrdenCompraDto(PropuestaOrdenCompraDto Propuesta, List<MonedaOrdenCompraDto> Monedas);

/// <summary>Datos de la OC (N° OC, fechas, moneda, monto, vigencia en días y observaciones).</summary>
public record DatosOrdenCompraDto
{
    public string?   NumeroOc       { get; init; }
    public DateTime? FechaOc        { get; init; }
    public DateTime? FechaRecepcion { get; init; }
    public int?      IdMoneda       { get; init; }
    public decimal?  Monto          { get; init; }
    public int?      VigenciaDias   { get; init; }
    public string?   Observaciones  { get; init; }
}

/// <summary>Datos que el caso de uso envía al SP (incluye el PDF ya guardado).</summary>
public record ComandoOrdenCompra(
    DatosOrdenCompraDto Datos,
    string?             RutaPdf,
    string?             NombrePdf,
    long?               TamanoPdf,
    string?             HashPdf);

/// <summary>
/// Indicador de cobertura. EstadoCobertura: completa | parcial | excede | moneda_diferente.
/// Diferencia = monto OC − monto propuesta (null si las monedas son distintas).
/// </summary>
public record CoberturaOrdenCompraDto(
    string   EstadoCobertura,
    decimal  CoberturaPct,
    decimal? Diferencia,
    decimal  MontoPropuesta,
    int      IdMonedaPropuesta,
    string?  MonedaSimboloPropuesta,
    decimal  MontoOc,
    int      IdMonedaOc,
    string?  MonedaSimboloOc);

/// <summary>OC registrada. Estado: pendiente_validacion. SiguienteEtapa: validacion_oc.</summary>
public record OrdenCompraRegistradaDto(
    long      IdOc,
    string    NumeroOc,
    string    Estado,
    string    EstadoCobertura,
    decimal   CoberturaPct,
    decimal?  Diferencia,
    DateTime? VigenciaHasta,
    string    SiguienteEtapa,
    int       Notificados);

public record RutaPdfOrdenCompraDto(string Ruta, string NombreArchivo);
