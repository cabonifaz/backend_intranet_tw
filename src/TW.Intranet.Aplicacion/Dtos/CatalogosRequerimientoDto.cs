namespace TW.Intranet.Aplicacion.Dtos;

public record CatalogosRequerimientoDto(
    List<CatalogoItemDto> Origenes,
    List<CatalogoItemDto> Areas,
    List<CatalogoItemDto> Prioridades
);
