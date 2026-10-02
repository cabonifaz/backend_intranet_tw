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
    bool   UsarEnPropuestas
);
