namespace TW.Intranet.Aplicacion.Dtos;

// ── Ubigeo INEI (sedes del cliente: departamento → provincia → distrito) ────────
/// <summary>Opción de ubigeo. Código INEI: 2 dígitos (departamento), 4 (provincia) o 6 (distrito).</summary>
public record UbigeoItemDto(string Codigo, string Nombre);

// ── Áreas por cliente (nombres libres, estado activo/inactivo) ─────────────────
/// <summary>
/// Área del cliente. Modelo por cliente (no catálogo global) — nombres libres
/// definidos por el usuario para describir las zonas operativas de los locales
/// del cliente (ej. "Zona de carnes", "Patio norte", "Laboratorio C").
/// Equipos. = conteo de equipos del cliente que la usan como ubicación.
/// </summary>
public record AreaClienteDto(long IdArea, long IdCliente, string Nombre, string Estado, int Equipos);

/// <summary>Body de POST /api/maestros/clientes/{idCliente}/areas. IdArea = 0 para crear.</summary>
public class GuardarAreaClienteDto
{
    public long    IdArea { get; set; }
    public string? Nombre { get; set; }
}

/// <summary>Body de PATCH /api/maestros/areas-cliente/{idArea}/estado. Estado: "Activo" | "Inactivo".</summary>
public class CambiarEstadoAreaClienteDto
{
    public string? Estado { get; set; }
}

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
