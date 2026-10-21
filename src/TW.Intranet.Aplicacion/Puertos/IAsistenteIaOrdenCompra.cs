using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// IA de órdenes de compra (Gemini): lee el PDF de la OC y evalúa sus conceptos contra los de cada propuesta.
/// La IA no decide: extrae datos, explica las diferencias y sugiere qué hacer. La comparación de los campos
/// estructurados (cliente, monto, moneda, forma de pago, IGV, fechas) la hacen las reglas de la base de datos.
/// </summary>
public interface IAsistenteIaOrdenCompra
{
    /// <summary>false si no hay API key configurada (Gemini__ApiKey): el módulo funciona con carga manual.</summary>
    bool Disponible { get; }

    /// <summary>Nombre del motor para el historial (ej. "gemini-3.5-flash-lite").</summary>
    string Motor { get; }

    /// <summary>Lee los datos de la OC desde el PDF. Si la IA no está disponible o falla, devuelve Error (no lanza excepción).</summary>
    Task<ResultadoIa<DatosExtraidosIaDto>> ExtraerAsync(byte[] pdf, CancellationToken ct);

    /// <summary>
    /// Compara los conceptos de la OC con los ítems de una propuesta y redacta el dictamen y los insights,
    /// considerando las diferencias que ya encontraron las reglas.
    /// </summary>
    Task<ResultadoIa<EvaluacionIaPropuestaDto>> EvaluarAsync(SolicitudEvaluacionIaDto solicitud, CancellationToken ct);
}

/// <summary>Resultado de una llamada a la IA: Datos o Error (nunca lanza excepción por fallas del servicio).</summary>
public record ResultadoIa<T>(T? Datos, string? Error) where T : class
{
    public bool Ok => Datos is not null;
}

/// <summary>Datos tal como los leyó la IA del PDF (moneda y condición de pago en texto, sin traducir al catálogo).</summary>
public record DatosExtraidosIaDto(
    string?   NumeroOc,
    DateTime? FechaEmision,
    string?   Ruc,
    string?   RazonSocial,
    string?   NumeroPropuesta,
    string?   Moneda,
    decimal?  MontoTotal,
    string?   FormaPago,
    string?   CondicionPagoCodigo,
    bool?     IgvIncluido,
    decimal?  IgvPct,
    decimal?  Descuento,
    DateTime? VigenciaHasta,
    List<ConceptoOrdenCompraDto> Conceptos,
    decimal?  Confianza);

/// <summary>Lo que necesita la IA para evaluar una vinculación OC ↔ propuesta.</summary>
public record SolicitudEvaluacionIaDto(
    long                          IdPropuesta,
    string                        NumeroPropuesta,
    string?                       MonedaSimbolo,
    IReadOnlyList<ConceptoOrdenCompraDto> ConceptosOc,
    IReadOnlyList<ItemPropuestaIaDto>     ItemsPropuesta,
    IReadOnlyList<CampoComparadoOcDto>    Diferencias,
    bool                          FacturaIgualOc,
    bool                          OcCubreVariasPropuestas);
