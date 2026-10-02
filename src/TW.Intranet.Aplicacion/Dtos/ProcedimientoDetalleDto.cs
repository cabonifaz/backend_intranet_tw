namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Ficha del procedimiento (HU-87). Coincide con ProcedimientoDetalle del front.</summary>
public record ProcedimientoDetalleDto(
    // Datos del listado
    long      IdProcedimiento,
    string    Codigo,
    int       Anio,
    int       Version,
    bool      EsFormatoDigitalIso,
    string    NormaBase,
    string    AutorNorma,
    string    Descripcion,
    string    Estado,
    DateTime? FechaRegistro,

    // 01 Identificación
    string    TipoProcedimiento,
    bool      EsActivo,

    // 02 Descripción y alcance
    string    Alcance,
    string    AprobadoPor,
    string    UrlPdfAprobado,

    // Trazabilidad
    string    UsuarioRegistro,
    string    PcRegistro,
    DateTime? FechaModificacion,
    int       TotalEdiciones
);
