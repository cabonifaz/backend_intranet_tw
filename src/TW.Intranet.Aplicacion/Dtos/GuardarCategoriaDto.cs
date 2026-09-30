namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarCategoriaDto(
    int      IdCategoria,
    string   Nombre,
    string?  Descripcion,
    int?     PrioridadAtencion,
    decimal? PctGananciaMin,
    decimal? PctGananciaMax
);
