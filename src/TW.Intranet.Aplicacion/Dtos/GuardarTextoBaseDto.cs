namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/textos-base. IdTextoBase = 0 para crear.</summary>
public class GuardarTextoBaseDto
{
    public long    IdTextoBase         { get; set; }
    public string? CodigoCorto         { get; set; }
    public string? TipoCategoria       { get; set; }
    public string? Nombre              { get; set; }
    public string? TextoClausula       { get; set; }
    public string? SeccionDossier      { get; set; }
    public int     OrdenAparicion      { get; set; } = 1;
    public string? NivelSangria        { get; set; }
    public bool    EsPredeterminado    { get; set; }
    public bool    EsNegritaPorDefecto { get; set; }
    public bool    Activo              { get; set; } = true;

    public bool AplicaCalibracionLab    { get; set; }
    public bool AplicaCalibracionPlanta { get; set; }
    public bool AplicaMantenimiento     { get; set; }
    public bool AplicaVentaSuministros  { get; set; }

    public bool VisibleGestoresComerciales { get; set; } = true;
    public bool VisibleTecnicosMetrologos  { get; set; } = true;
    public bool VisibleSupervisores        { get; set; } = true;

    public bool GuardarComoBorrador { get; set; }
}
