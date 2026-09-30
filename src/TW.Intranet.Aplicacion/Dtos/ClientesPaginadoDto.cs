namespace TW.Intranet.Aplicacion.Dtos;

public record ClientesPaginadoDto(
    List<ClienteListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
