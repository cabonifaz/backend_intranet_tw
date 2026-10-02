namespace TW.Intranet.Aplicacion.Dtos;

public class CambiarEstadoSuministroDto
{
    public long    IdSuministro { get; set; }
    /// <summary>"Activo" o "Inactivo".</summary>
    public string? Estado       { get; set; }
}
