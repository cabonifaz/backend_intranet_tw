namespace TW.Intranet.Aplicacion.Dtos;

public record EquiposClientePaginadoDto(
    List<EquipoClienteListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
