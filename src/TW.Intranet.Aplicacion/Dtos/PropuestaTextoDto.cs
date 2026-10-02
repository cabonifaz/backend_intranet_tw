namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Texto de una sección (Detalle, Recomendaciones, Suministros del Cliente, Condiciones).
/// Jerarquía por orden: cada "vineta" pertenece al último "titulo" anterior.
/// </summary>
public class PropuestaTextoDto
{
    public long?   Id          { get; set; }
    /// <summary>"detalle" | "recomendaciones" | "suministros_cliente" | "condiciones".</summary>
    public string? Seccion     { get; set; }
    /// <summary>"titulo" o "vineta".</summary>
    public string? Tipo        { get; set; } = "vineta";
    public string? Texto       { get; set; }
    /// <summary>Texto base de origen (HU-85), si se tomó del catálogo.</summary>
    public long?   IdTextoBase { get; set; }
    public int     Orden       { get; set; }
}
