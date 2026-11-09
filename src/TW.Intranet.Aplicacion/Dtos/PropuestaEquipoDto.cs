namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Equipo de la propuesta. Si IdEquipo apunta a equipo_cliente (HU-88), serie/marca/modelo
/// se toman del maestro. Si es manual, quedan fijos desde el primer guardado
/// (en ediciones se ignoran los cambios a esos tres campos).
/// </summary>
public class PropuestaEquipoDto
{
    /// <summary>Id de la fila en la propuesta (null si es nueva).</summary>
    public long?   Id            { get; set; }
    /// <summary>equipo_cliente.id_equipo. Null si se ingresó manualmente.</summary>
    public long?   IdEquipo      { get; set; }
    public string? LocalSede     { get; set; }
    public string? Tipo          { get; set; }
    public string? Subtipo       { get; set; }
    public string? NumSerie      { get; set; }
    public string? Marca         { get; set; }
    public string? Modelo        { get; set; }
    public string? CodigoCliente { get; set; }
    public string? CodigoTw      { get; set; }
    public int     Orden         { get; set; }

    // Solo lectura (observaciones 31/10): estado real del equipo en el maestro. Se ignoran al guardar.
    /// <summary>activo | inactivo | borrador (equipo_cliente.estado).</summary>
    public string? EstadoEquipo         { get; set; }
    /// <summary>Activo | Inactivo | Borrador.</summary>
    public string? EstadoEquipoLabel    { get; set; }
    /// <summary>En oficina | En evaluación | En ejecución (si tiene).</summary>
    public string? EstadoOperativoLabel { get; set; }
    /// <summary>Activo | Inactivo | Borrador (estado del equipo en el maestro). Null si el equipo no está en el maestro.</summary>
    public string? Estado               { get; set; }
}
