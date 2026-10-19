namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/procedimientos. IdProcedimiento = 0 para crear.</summary>
public class GuardarProcedimientoDto
{
    public long    IdProcedimiento     { get; set; }
    public string? Codigo              { get; set; }
    public int     Anio                { get; set; }
    /// <summary>Al editar, si es menor o igual a la actual, el back la incrementa automáticamente.</summary>
    public int     Version             { get; set; } = 1;
    public string? AutorNorma          { get; set; }
    public string? NormaBase           { get; set; }
    public string? Descripcion         { get; set; }
    public bool    EsFormatoDigitalIso { get; set; }
    /// <summary>
    /// IGNORADO: se mantiene por compatibilidad. El PDF aprobado se carga con
    /// POST /api/maestros/procedimientos/{id}/pdf (acción procedimiento_pdf_cargar).
    /// </summary>
    public string? UrlPdfAprobado      { get; set; }
    public bool    EsActivo            { get; set; } = true;
    public bool    GuardarComoBorrador { get; set; }
}
