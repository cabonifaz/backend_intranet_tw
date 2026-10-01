namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Ficha del suministro (HU-86). Coincide con SuministroDetalle del front.</summary>
public record SuministroDetalleDto(
    // Datos del listado
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

    // Descripciones
    string DescripcionAuto,
    string DescripcionManual,

    // Alcance y logística
    string Alcance,
    string Unidad,
    string Casillero,

    // Panel cotización
    string                CodigoUnspsc,
    decimal?              PrecioMinReferencia,
    List<EscalaTarifaDto> Escalas,
    bool                  AplicaComercial,
    bool                  AplicaServicio,
    bool                  AplicaMetrologia,

    // Procedimientos (solo clase "servicio")
    string? IdPrimerProcedimiento,
    string? IdSegundoProcedimiento,

    // Trazabilidad
    string    UsuarioRegistro,
    DateTime? FechaRegistro,
    DateTime? FechaModificacion,
    int       TotalEdiciones,
    string    FirmaDigital,

    // Adjuntos (aún sin carga real de archivos)
    string UrlFoto,
    string UrlManualPdf
);
