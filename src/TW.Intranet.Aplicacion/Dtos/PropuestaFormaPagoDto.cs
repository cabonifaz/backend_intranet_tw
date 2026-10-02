namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Hito de pago. La suma de porcentajes debe ser 100.</summary>
public class PropuestaFormaPagoDto
{
    public long?   Id             { get; set; }
    public decimal Porcentaje     { get; set; }
    /// <summary>Código del catálogo CONDICION_PAGO (ej. "CREDITO_30").</summary>
    public string? Condicion      { get; set; }
    /// <summary>Solo lectura: etiqueta del catálogo.</summary>
    public string? CondicionLabel { get; set; }
    public int     Orden          { get; set; }
}
