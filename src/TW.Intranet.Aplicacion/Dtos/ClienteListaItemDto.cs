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
    int     CantidadContactos,
    // Reunión 02-oct: el listado muestra el contacto principal (reemplaza a condición fiscal en el front)
    string? ContactoPrincipal       = null,
    string? ContactoPrincipalCorreo = null
);