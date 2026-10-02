namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/catalogos/{descripcion}.</summary>
public class AgregarItemCatalogoDto
{
    /// <summary>Etiqueta visible (ej. "RADWAG").</summary>
    public string? String1 { get; set; }
    /// <summary>Código (ej. "radwag"). Si viene vacío se genera a partir de String1.</summary>
    public string? String2 { get; set; }
}
