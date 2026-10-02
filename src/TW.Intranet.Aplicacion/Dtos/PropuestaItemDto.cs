namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Ítem de la propuesta (secciones "Propuesta" y "Opcionales"). Se usa al guardar y al leer.</summary>
public class PropuestaItemDto
{
    public long?   IdItem            { get; set; }
    /// <summary>"principal" o "opcional".</summary>
    public string? Seccion           { get; set; } = "principal";
    /// <summary>Suministro/servicio del catálogo (HU-86). Null si es libre o espaciado.</summary>
    public long?   IdCatalogoItem    { get; set; }
    public string? Descripcion       { get; set; }
    public string? Alcance           { get; set; }
    public string? PuntosCalibracion { get; set; }
    public decimal Cantidad          { get; set; }
    public decimal Frecuencia        { get; set; } = 1;
    public decimal PrecioUnitario    { get; set; }
    /// <summary>Descuento en monto para este ítem.</summary>
    public decimal Descuento         { get; set; }
    /// <summary>Calculado por el back: cantidad × frecuencia × precio − descuento.</summary>
    public decimal Subtotal          { get; set; }
    /// <summary>Fila vacía de separación ("Añadir espaciado"). No suma.</summary>
    public bool    EsEspaciado       { get; set; }
    public int     Orden             { get; set; }
}
