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
    [Required][StringLength(500)] string  DireccionExacta
);
