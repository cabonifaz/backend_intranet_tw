namespace TW.Intranet.Aplicacion.Dtos;

// App Mobile HU-24 — Biblioteca de procedimientos

/// <summary>Una versión anterior (ya reemplazada: no se puede usar).</summary>
public record VersionProcedimientoMovilDto(int Version, string? ReemplazadaEl);

/// <summary>
/// Procedimiento aprobado con PDF. <c>ParaServicioHoy</c> = número de la OS de hoy del técnico que lo usa (la app lo descarga sola al iniciar la jornada).
/// <c>PdfHash</c> permite a la app saber si el PDF guardado en el teléfono es el vigente.
/// </summary>
public record ProcedimientoMovilDto(
    long IdProcedimiento,
    string Codigo,
    int Anio,
    int Version,
    string? NormaBase,
    string? AutorNorma,
    string? Tipo,
    string Descripcion,
    string? Alcance,
    string? AprobadoPor,
    string? Actualizado,
    string? PdfNombre,
    long? PdfTamanoBytes,
    string? PdfHash,
    string? ParaServicioHoy,
    IReadOnlyList<VersionProcedimientoMovilDto> Historial);

public record BibliotecaProcedimientosMovilDto(IReadOnlyList<ProcedimientoMovilDto> Procedimientos);
