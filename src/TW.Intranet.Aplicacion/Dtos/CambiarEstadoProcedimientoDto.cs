namespace TW.Intranet.Aplicacion.Dtos;

public class CambiarEstadoProcedimientoDto
{
    public long    IdProcedimiento { get; set; }
    /// <summary>"Activo" o "Inactivo".</summary>
    public string? Estado          { get; set; }
}
