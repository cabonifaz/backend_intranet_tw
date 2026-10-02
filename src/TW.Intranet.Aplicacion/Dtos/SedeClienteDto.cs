namespace TW.Intranet.Aplicacion.Dtos;

public record SedeClienteDto(
    long    IdSede,
    long    IdCliente,
    string  Nombre,
    string? TipoInstalacion,
    string? Region,
    string? Provincia,
    string? Distrito,
    string? Urbanizacion,
    string? DireccionExacta,
    string  Estado
);
