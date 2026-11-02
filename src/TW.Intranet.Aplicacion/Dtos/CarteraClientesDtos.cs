using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Cartera de clientes (observación 31/10): filtros del listado.
/// Asignacion: "" | todos | asignados | sin_asignar. IdComercial: filtra por comercial (solo administrador).
/// </summary>
public record FiltrosCarteraClientesDto
{
    public long?   IdComercial { get; init; }
    public string? Busqueda    { get; init; }
    public string? Asignacion  { get; init; }
    public int     Pagina      { get; init; } = 1;
    public int     PorPagina   { get; init; } = 20;
}

public record ClienteCarteraDto(
    long      IdCliente,
    string    RazonSocial,
    string?   Ruc,
    string?   Estado,
    long?     IdComercial,
    string?   Comercial,
    DateTime? AsignadoEn,
    string?   AsignadoPor
);

public record ComercialCarteraDto(long Id, string Nombre, string? Cargo, int Clientes);

/// <summary>PuedeAsignar = el usuario tiene la acción cartera_asignar (Administrador).</summary>
public record CarteraClientesDto(
    IReadOnlyList<ClienteCarteraDto>   Items,
    int                                Total,
    int                                Pagina,
    int                                PorPagina,
    IReadOnlyList<ComercialCarteraDto> Comerciales,
    bool                               PuedeAsignar
);

/// <summary>IdComercial null o 0 = quitar los clientes de la cartera.</summary>
public record AsignarCarteraClientesComandoDto(
    long? IdComercial,
    [Required, MinLength(1, ErrorMessage = "Seleccione al menos un cliente.")]
    IReadOnlyList<long> IdsClientes
);
