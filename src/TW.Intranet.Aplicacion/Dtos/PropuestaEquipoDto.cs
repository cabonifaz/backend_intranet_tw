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
}
