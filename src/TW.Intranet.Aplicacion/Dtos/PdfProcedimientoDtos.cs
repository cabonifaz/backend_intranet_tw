namespace TW.Intranet.Aplicacion.Dtos;

// ─────────────────────────────────────────────────────────────────────────────
// HU-87 — Carga real del PDF aprobado de Procedimientos
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>GET /api/maestros/procedimientos/pdf/permiso — si el usuario actual puede cargar el PDF.</summary>
public record PermisoPdfProcedimientoDto(bool PuedeSubirPdf, string? Motivo);

/// <summary>Respuesta de POST /api/maestros/procedimientos/{id}/pdf.</summary>
/// <param name="UrlPdf">Endpoint para ver el PDF (requiere token): /api/maestros/procedimientos/{id}/pdf</param>
public record PdfProcedimientoDto(
    string    NombreArchivo,
    long      TamanoBytes,
    DateTime? SubidoEn,
    string?   SubidoPor,
    string    UrlPdf
);

/// <summary>Uso interno (puerto → caso de uso): dónde está guardado el PDF.</summary>
public record RutaPdfProcedimientoDto(string Ruta, string NombreArchivo);

/// <summary>Archivo listo para enviarse al cliente HTTP. El controller cierra el stream.</summary>
public record ArchivoDescargaDto(Stream Contenido, string NombreArchivo, string TipoContenido);
