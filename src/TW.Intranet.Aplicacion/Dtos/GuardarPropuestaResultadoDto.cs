namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Respuesta del guardado: identificador y totales recalculados por el back (panel lateral).</summary>
public record GuardarPropuestaResultadoDto(
    long    IdPropuesta,
    string  Numero,
    int     Version,
    decimal Subtotal,
    decimal DescuentoMonto,
    decimal IgvMonto,
    decimal Total,
    decimal SubtotalOpcionales,
    decimal DescuentoOpcionales,
    decimal TotalOpcionales
);
