namespace TW.Intranet.Aplicacion.Dtos;

public record RequerimientosPaginadoDto(
    KpisRequerimientosDto          Kpis,
    List<RequerimientoListaItemDto> Items,
    int                            Total,
    int                            Pagina,
    int                            PorPagina
);
