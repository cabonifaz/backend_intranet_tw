namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Ruta por calles entre dos puntos: distancia (m) y tiempo (min) ya ajustado por tráfico.</summary>
public record RutaCarretera(int DistanciaM, int Minutos);

/// <summary>Servicio externo de rutas por calles (OSRM). Nunca lanza: si falla o no responde a tiempo devuelve null y quien llama usa su cálculo de respaldo.</summary>
public interface IProveedorRutas
{
    Task<RutaCarretera?> CalcularAsync(decimal latOrigen, decimal lonOrigen, decimal latDestino, decimal lonDestino, CancellationToken ct);

}
