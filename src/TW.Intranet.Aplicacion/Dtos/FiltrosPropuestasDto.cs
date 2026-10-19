namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Filtros de la bandeja de propuestas (query string de GET /api/crm/propuestas).</summary>
public class FiltrosPropuestasDto
{
    public long?   IdRequerimiento   { get; set; }
    /// <summary>Estado exacto en BD (opcional).</summary>
    public string? Estado            { get; set; }
    /// <summary>Pestaña: todas | borrador | por_vb | en_seguimiento | aceptada | rechazada | cerrada.</summary>
    public string? GrupoEstado       { get; set; }
    public string? Busqueda          { get; set; }
    public int?    Anio              { get; set; }
    /// <summary>id_usuario del comercial responsable.</summary>
    public long?   IdComercial       { get; set; }
    /// <summary>true (por defecto): solo la última versión de cada propuesta.</summary>
    public bool    SoloUltimaVersion { get; set; } = true;
    public int     Pagina            { get; set; } = 1;
    public int     PorPagina         { get; set; } = 10;
}
