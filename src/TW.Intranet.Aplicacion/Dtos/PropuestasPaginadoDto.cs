namespace TW.Intranet.Aplicacion.Dtos;

public record PropuestasPaginadoDto(
    List<PropuestaResumenDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
