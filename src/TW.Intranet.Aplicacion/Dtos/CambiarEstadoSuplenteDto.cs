namespace TW.Intranet.Aplicacion.Dtos;

public class CambiarEstadoSuplenteDto
{
    public long    IdAsignacion { get; set; }
    /// <summary>"Activo" o "Inactivo".</summary>
    public string? Estado       { get; set; }
}
