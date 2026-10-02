namespace TW.Intranet.Aplicacion.Dtos;

public record SuministrosPaginadoDto(
    List<SuministroListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
