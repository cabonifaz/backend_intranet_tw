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
    bool      EsActivo,

    // 02 Documento aprobado
    string    UrlPdfAprobado,

    // Trazabilidad
    string    UsuarioRegistro,
    string    PcRegistro,
    DateTime? FechaModificacion,
    int       TotalEdiciones
);
