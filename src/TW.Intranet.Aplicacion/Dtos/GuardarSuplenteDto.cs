namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/suplentes. IdAsignacion = 0 para crear.</summary>
public class GuardarSuplenteDto
{
    public long    IdAsignacion { get; set; }
    public long    IdTitular    { get; set; }
    public long    IdSuplente   { get; set; }
    /// <summary>Formato yyyy-MM-dd.</summary>
    public string? FechaInicio  { get; set; }
    /// <summary>Formato yyyy-MM-dd. Se ignora si SinFechaFin = true.</summary>
    public string? FechaFin     { get; set; }
    public bool    SinFechaFin  { get; set; }
    public bool    Activo       { get; set; } = true;
}
