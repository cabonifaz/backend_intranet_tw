namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de suministros (HU-86). Coincide con SuministroListaItem del front.</summary>
public record SuministroListaItemDto(
    long   IdSuministro,
    string Codigo,
    string Clase,
    string ClaseLabel,
    string Tipo,
    string TipoLabel,
    string Subtipo,
    string SubtipoLabel,
    string Descripcion,
    string Marca,
    string Modelo,
    string CtaContable,
    string Procedencia,
    string ProcedenciaLabel,
    string Estado,
    bool   EsActivoEnCatalogo,
    bool   UsarEnPropuestas,
    /// <summary>Observaciones 31/10: procedimientos técnicos (para la descripción del ítem en la propuesta).</summary>
    /// <summary>Código del procedimiento (ej. "TW-CAL-01"), igual que en el detalle del suministro.</summary>
    string? IdPrimerProcedimiento  = null,
    string? PrimerProcedimiento    = null,
    string? IdSegundoProcedimiento = null,
    string? SegundoProcedimiento   = null
);
