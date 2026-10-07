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
    // UrlPdfAprobado: endpoint para ver el PDF (GET, requiere token) o "" si aún no se cargó
    string    UrlPdfAprobado,

    // Trazabilidad
    string    UsuarioRegistro,
    string    PcRegistro,
    DateTime? FechaModificacion,
    int       TotalEdiciones,

    // PDF aprobado cargado (carga real, restringida a la encargada de calidad)
    bool      TienePdf          = false,
    string?   PdfNombreArchivo  = null,
    long?     PdfTamanoBytes    = null,
    DateTime? PdfSubidoEn       = null,
    string?   PdfSubidoPor      = null
);
