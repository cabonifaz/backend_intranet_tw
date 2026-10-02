namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/suministros. IdSuministro = 0 para crear.</summary>
public class GuardarSuministroDto
{
    public long    IdSuministro       { get; set; }
    public string? Clase              { get; set; }
    public string? Tipo               { get; set; }
    public string? Subtipo            { get; set; }
    /// <summary>Vacío si Clase = "servicio".</summary>
    public string? Marca              { get; set; }
    /// <summary>Vacío si Clase = "servicio".</summary>
    public string? Modelo             { get; set; }
    public string? DescripcionAuto    { get; set; }
    public string? DescripcionManual  { get; set; }
    public string? Alcance            { get; set; }
    public string? Unidad             { get; set; }
    public string? CtaContable        { get; set; }
    public string? Procedencia        { get; set; }
    public string? Casillero          { get; set; }
    public bool    EsActivoEnCatalogo { get; set; } = true;

    public bool                   UsarEnPropuestas    { get; set; }
    public string?                CodigoUnspsc        { get; set; }
    public decimal?               PrecioMinReferencia { get; set; }
    public List<EscalaTarifaDto>? Escalas             { get; set; }
    public bool                   AplicaComercial     { get; set; }
    public bool                   AplicaServicio      { get; set; }
    public bool                   AplicaMetrologia    { get; set; }

    /// <summary>Solo para Clase = "servicio".</summary>
    public string? IdPrimerProcedimiento  { get; set; }
    public string? IdSegundoProcedimiento { get; set; }

    public bool GuardarComoBorrador { get; set; }
}
