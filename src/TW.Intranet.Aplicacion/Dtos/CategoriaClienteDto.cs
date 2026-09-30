namespace TW.Intranet.Aplicacion.Dtos;

public record CategoriaClienteDto(
    int      IdCategoria,
    string   Nombre,
    string?  Descripcion,
    int?     PrioridadAtencion,
    decimal? PctGananciaMin,
    decimal? PctGananciaMax,
    string   Estado
);
