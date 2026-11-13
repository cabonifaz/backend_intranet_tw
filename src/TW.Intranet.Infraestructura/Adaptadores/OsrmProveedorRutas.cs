using System.Globalization;
using System.Text.Json;
using System.Collections.Concurrent;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Ruta por calles con OSRM (OpenStreetMap), gratuito y sin llave; para producción se puede alojar uno propio cambiando "Rutas:OsrmUrl". OSRM no conoce el tráfico: el tiempo se multiplica por "Rutas:FactorTrafico" (1.3 por defecto).
/// Solo se envían coordenadas; los resultados se guardan en memoria para no repetir consultas.
/// </summary>
public class OsrmProveedorRutas(HttpClient http, ConfiguracionRutas configuracion) : IProveedorRutas
{
    private readonly string _osrm = configuracion.OsrmUrl.TrimEnd('/');
    private readonly double _factorTrafico = configuracion.FactorTrafico is >= 1 and <= 3 ? configuracion.FactorTrafico : 1.3;

    // Caché en memoria con vencimiento (clave → valor, hasta cuándo)
    private static readonly ConcurrentDictionary<string, (DateTime Hasta, object? Valor)> Cache = new();

    private static bool Leer<T>(string clave, out T? valor)
    {
        if (Cache.TryGetValue(clave, out var e) && e.Hasta > DateTime.UtcNow) { valor = (T?)e.Valor; return true; }
        valor = default;
        return false;
    }

    private static void Guardar(string clave, object? valor, TimeSpan vida)
    {
        if (Cache.Count > 2000) foreach (var k in Cache.Where(x => x.Value.Hasta <= DateTime.UtcNow).Select(x => x.Key).ToList()) Cache.TryRemove(k, out _);
        Cache[clave] = (DateTime.UtcNow + vida, valor);
    }

    private static string N(decimal v, int dec) => Math.Round(v, dec).ToString(CultureInfo.InvariantCulture);

    public async Task<RutaCarretera?> CalcularAsync(decimal latOrigen, decimal lonOrigen, decimal latDestino, decimal lonDestino, CancellationToken ct)
    {
        // El origen se redondea a ~100 m: un técnico que se mueve poco reutiliza la respuesta durante un minuto
        var clave = $"ruta:{N(latOrigen, 3)},{N(lonOrigen, 3)}>{N(latDestino, 5)},{N(lonDestino, 5)}";
        if (Leer<RutaCarretera?>(clave, out var guardada)) return guardada;

        RutaCarretera? ruta = null;
        try
        {
            var url = $"{_osrm}/route/v1/driving/{N(lonOrigen, 6)},{N(latOrigen, 6)};{N(lonDestino, 6)},{N(latDestino, 6)}?overview=false";
            using var tiempo = CancellationTokenSource.CreateLinkedTokenSource(ct);
            tiempo.CancelAfter(TimeSpan.FromSeconds(4));
            using var resp = await http.GetAsync(url, tiempo.Token);
            if (resp.IsSuccessStatusCode)
            {
                using var doc = await JsonDocument.ParseAsync(await resp.Content.ReadAsStreamAsync(tiempo.Token), cancellationToken: tiempo.Token);
                if (doc.RootElement.TryGetProperty("routes", out var rutas) && rutas.GetArrayLength() > 0)
                {
                    var r = rutas[0];
                    var metros   = r.GetProperty("distance").GetDouble();
                    var segundos = r.GetProperty("duration").GetDouble();
                    ruta = new RutaCarretera((int)Math.Round(metros), Math.Max(1, (int)Math.Ceiling(segundos * _factorTrafico / 60.0)));
                }
            }
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            // sin servicio externo: quien llama usa su cálculo de respaldo
        }

        Guardar(clave, ruta, ruta is null ? TimeSpan.FromSeconds(20) : TimeSpan.FromSeconds(60));
        return ruta;
    }

}
