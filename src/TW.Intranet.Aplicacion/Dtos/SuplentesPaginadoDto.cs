namespace TW.Intranet.Aplicacion.Dtos;

public record SuplentesPaginadoDto(
    List<SuplenteListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
