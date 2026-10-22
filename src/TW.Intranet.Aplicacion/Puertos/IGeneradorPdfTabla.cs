namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Documento PDF de una tabla (exportaciones de consulta): título, subtítulo y una hoja con encabezados y filas.</summary>
public record DocumentoTablaPdf(string Titulo, string? Subtitulo, HojaExcel Tabla, string? PiePagina = null);

/// <summary>HU-32 — Genera un PDF horizontal con una tabla (ej. el tab activo del historial de auditoría).</summary>
public interface IGeneradorPdfTabla
{
    byte[] Generar(DocumentoTablaPdf documento);
}
