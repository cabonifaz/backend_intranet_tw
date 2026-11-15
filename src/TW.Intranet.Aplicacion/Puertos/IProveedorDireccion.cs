namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// Dirección legible de una coordenada (calle y número, o barrio/caserío) desde un servicio externo (Nominatim / OpenStreetMap).
/// Nunca lanza: si falla, no responde a tiempo o no hay dirección, devuelve null.
/// </summary>
public interface IProveedorDireccion
{
    Task<string?> ObtenerDireccionAsync(decimal latitud, decimal longitud, CancellationToken ct);
}
