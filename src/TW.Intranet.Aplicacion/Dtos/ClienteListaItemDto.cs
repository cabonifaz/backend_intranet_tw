namespace TW.Intranet.Aplicacion.Dtos;

public record ClienteListaItemDto(
    long    IdCliente,
    string  Ruc,
    string  Codigo,
    string  RazonSocial,
    string? NombreComercial,
    string  TipoCliente,
    string  CondicionFiscal,
    string  CondicionContribuyente,
    bool    EsVip,
    string  Estado,
    string? SedeNombre,
    string? SedeRegion,
    int     CantidadContactos
);
