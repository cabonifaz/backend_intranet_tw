namespace TW.Intranet.Aplicacion.Dtos;

public class CambiarEstadoTextoBaseDto
{
    public long    IdTextoBase { get; set; }
    /// <summary>"Activo" o "Inactivo".</summary>
    public string? Estado      { get; set; }
}
