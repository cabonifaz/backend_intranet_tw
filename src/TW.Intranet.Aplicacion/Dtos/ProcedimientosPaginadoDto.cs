namespace TW.Intranet.Aplicacion.Dtos;

public record ProcedimientosPaginadoDto(
    List<ProcedimientoListaItemDto> Items,
    int Total,
    int Pagina,
    int PorPagina
);
