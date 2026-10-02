namespace TW.Intranet.Aplicacion.Dtos;

public record TextosBasePaginadoDto(
    List<TextoBaseListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
