namespace TW.Intranet.Aplicacion.Dtos;

public class CambiarEstadoEquipoClienteDto
{
    public long    IdEquipo { get; set; }
    /// <summary>"Activo" o "Inactivo".</summary>
    public string? Estado   { get; set; }
}
