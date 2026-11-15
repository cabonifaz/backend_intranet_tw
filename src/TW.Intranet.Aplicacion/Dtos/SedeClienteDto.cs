namespace TW.Intranet.Aplicacion.Dtos;

public record SedeClienteDto(
    long    IdSede,
    long    IdCliente,
    string  Nombre,
    string? TipoInstalacion,
    string? Region,
    string? Provincia,
    string? Distrito,
    string? Referencia,
    string? DireccionExacta,
    string  Estado,
    decimal? Latitud  = null,
    decimal? Longitud = null
)
{
    /// <summary>TRANSICIÓN: mismo valor que Referencia con el nombre viejo, mientras el front no se actualice. Quitar cuando el front lea "referencia".</summary>
    public string? Urbanizacion => Referencia;
}
