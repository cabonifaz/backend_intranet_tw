namespace TW.Intranet.Aplicacion.Dtos;

// ── Ubigeo INEI (sedes del cliente: departamento → provincia → distrito) ────────
/// <summary>Opción de ubigeo. Código INEI: 2 dígitos (departamento), 4 (provincia) o 6 (distrito).</summary>
public record UbigeoItemDto(string Codigo, string Nombre);

// ── Áreas asignadas al cliente (catálogo AREA_USUARIO): "ubicación" de los equipos ──
/// <summary>Área asignada al cliente. Codigo = String2 de AREA_USUARIO (lo que se guarda en el equipo).</summary>
public record AreaClienteDto(string Codigo, string Nombre);

// ── Próximo código de una ficha en modo "nuevo" (referencial) ──────────────────
public record SiguienteCodigoDto(string Entidad, string Codigo);

// ── Códigos de formato por ventana (calidad / procedimientos acreditados) ──────
/// <summary>
/// Código que se muestra en cada ficha (crear y editar usan el mismo).
/// Etiqueta = CodigoFormato + "-" + Version (ej. "MTW97-10"). Null mientras TW no lo asigne.
/// </summary>
public record FormatoVentanaDto(
    string    Clave,
    string    NombreVentana,
    string?   CodigoFormato,
    int?      Version,
    string?   Etiqueta,
    DateTime? FechaModificacion);

/// <summary>Body de PUT /api/maestros/formatos-ventana/{clave}.</summary>
public class GuardarFormatoVentanaDto
{
    /// <summary>Obligatorio solo si la clave es nueva.</summary>
    public string? NombreVentana { get; set; }
    /// <summary>Ej. "MTW97". Vacío = quitar el código.</summary>
    public string? CodigoFormato { get; set; }
    public int?    Version       { get; set; }
}
