namespace TW.Intranet.Aplicacion.Dtos;

// ── Ubigeo INEI (sedes del cliente: departamento → provincia → distrito) ────────
/// <summary>Opción de ubigeo. Código INEI: 2 dígitos (departamento), 4 (provincia) o 6 (distrito).</summary>
public record UbigeoItemDto(string Codigo, string Nombre);

/// <summary>
/// Ubigeo de una coordenada (pin del mapa de la sede). Los nombres son los mismos de los selects en cascada.
/// Aproximado = true cuando el punto no cayó dentro de ningún distrito y se tomó el más cercano (a menos de ~1 km).
/// </summary>
public record UbigeoReversoDto(UbigeoItemDto Departamento, UbigeoItemDto Provincia, UbigeoItemDto Distrito, string Ubigeo, bool Aproximado);

/// <summary>Sede activa sin ubicación en el mapa. Primero las que tienen servicios próximos (ProximoServicio = yyyy-MM-dd).</summary>
public record SedeSinUbicacionDto(
    long IdSede, long IdCliente, string Cliente, string Sede, string? DireccionExacta, string? Region, string? Provincia, string? Distrito,
    int ServiciosProximos, string? ProximoServicio);

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

// ── Requisitos SSOMA asignados al cliente ────────────────────────────────────
/// <summary>Requisito SSOMA aplicable al cliente. codigo = String2 del catálogo REQUISITO_SSOMA.</summary>
public record RequisitoSsomaClienteDto(string Codigo, string Nombre);

/// <summary>
/// Body de PUT /api/maestros/clientes/{idCliente}/requisitos-ssoma.
/// Reemplaza la lista completa de requisitos aplicables al cliente (delete + insert).
/// </summary>
public class SincronizarRequisitosSsomaDto
{
    /// <summary>Códigos (String2 del catálogo REQUISITO_SSOMA). Lista vacía = quita todos los requisitos.</summary>
    public List<string>? Codigos { get; set; }
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
