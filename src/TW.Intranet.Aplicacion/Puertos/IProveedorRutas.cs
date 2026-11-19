namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Ruta por calles entre dos puntos: distancia (m), tiempo (min) ya ajustado por tráfico y el trazado por las calles (puntos en orden, para dibujarlo en el mapa; hasta ~200).</summary>
public record RutaCarretera(int DistanciaM, int Minutos, IReadOnlyList<(decimal Latitud, decimal Longitud)>? Calles = null);

/// <summary>Servicio externo de rutas por calles (OSRM). Nunca lanza: si falla o no responde a tiempo devuelve null y quien llama usa su cálculo de respaldo.</summary>
public interface IProveedorRutas
{
    Task<RutaCarretera?> CalcularAsync(decimal latOrigen, decimal lonOrigen, decimal latDestino, decimal lonDestino, CancellationToken ct);

}
