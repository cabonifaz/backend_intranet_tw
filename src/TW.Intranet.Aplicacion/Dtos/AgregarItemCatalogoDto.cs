namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/catalogos/{descripcion}.</summary>
public class AgregarItemCatalogoDto
{
    /// <summary>Etiqueta visible (ej. "RADWAG").</summary>
    public string? String1 { get; set; }
    /// <summary>Código (ej. "radwag"). Si viene vacío se genera a partir de String1.</summary>
    public string? String2 { get; set; }
    /// <summary>Solo para TIPO_SUMINISTRO (obligatorio): clase del tipo (servicio | equipo | instrumento | pesa).</summary>
    public string? String3 { get; set; }
}

/// <summary>Body de PUT /api/maestros/catalogos/{descripcion}/{codigo}: nuevo nombre visible.</summary>
public class EditarItemCatalogoDto
{
    public string? String1 { get; set; }
}
