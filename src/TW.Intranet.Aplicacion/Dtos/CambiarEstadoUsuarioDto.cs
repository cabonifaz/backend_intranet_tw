namespace TW.Intranet.Aplicacion.Dtos;

public class CambiarEstadoUsuarioDto
{
    public long    IdUsuario { get; set; }
    /// <summary>"Activo" o "Inactivo".</summary>
    public string? Estado    { get; set; }
}
