namespace TW.Intranet.Aplicacion.Dtos;

public record SedeOperativaDto(
    int     IdSede,
    string  Nombre,
    string? Ubicacion,
    string? Tipo
);
