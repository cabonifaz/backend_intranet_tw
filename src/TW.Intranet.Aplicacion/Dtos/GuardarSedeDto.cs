using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarSedeDto(
    long    IdSede,
    long    IdCliente,
    [Required][StringLength(200)] string  Nombre,
    [StringLength(100)]           string? TipoInstalacion,
    [Required][StringLength(100)] string? Region,
    [Required][StringLength(100)] string? Provincia,
    [Required][StringLength(100)] string? Distrito,
    [StringLength(200)]           string? Urbanizacion,
    [Required][StringLength(500)] string  DireccionExacta,
    // Ubicación exacta de la planta (pin del mapa). Las dos o ninguna; al editar, null = se conserva la actual.
    // El rango de Perú lo valida SP_GuardarSede (responde 400 con el mensaje de negocio).
    decimal? Latitud  = null,
    decimal? Longitud = null,
    // true = borra la ubicación guardada (al editar).
    bool QuitarUbicacion = false
);
