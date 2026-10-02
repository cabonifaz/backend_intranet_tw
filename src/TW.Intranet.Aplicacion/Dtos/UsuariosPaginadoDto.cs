namespace TW.Intranet.Aplicacion.Dtos;

public record UsuariosPaginadoDto(
    List<UsuarioListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
