namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de equipos del cliente (HU-88). Coincide con EquipoClienteListaItem del front.</summary>
public record EquipoClienteListaItemDto(
    long   IdEquipo,
    string NumSerie,
    long   IdCliente,
    string ClienteRazonSocial,
    long   IdSede,
    string SedeNombre,
    string CodigoCliente,
    string CodigoTw,
    string Clasificacion,
    string ClasificacionLabel,
    string Marca,
    string Modelo,
    string Estado,
    bool   EsActivo
);
