using System.Globalization;
using System.Text.Json;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// App Mobile HU-17 — Lógica pura de las firmas por dispositivo. La firma llega como TRAZOS normalizados:
///   {"trazos":[[[x,y],[x,y],…],[[x,y],…]]} con x e y entre 0 y 1 (un trazo por cada vez que el dedo toca la pantalla).
///   · Validar: forma, límites (≤ 40 trazos, ≤ 2000 puntos, valores finitos de 0 a 1) y que no sea una rayita (extensión mínima y puntos suficientes).
///   · Similitud (0 a 100): se junta el recorrido de todos los trazos, se remuestrea a 64 puntos por longitud de arco, se centra y se escala por su radio (así no
///     importa dónde ni de qué tamaño se dibujó) y se mide la distancia media punto a punto. 100 = idéntica. Una firma copiada o repetida por otro responsable
///     queda muy cerca de 100; dos firmas distintas, muy por debajo del umbral (90 por defecto).
/// </summary>
public static class ComparadorFirmas
{
    public const int MaxTrazos = 40;
    public const int MaxPuntos = 2000;
    public const int MinPuntos = 12;
    public const int MaxCaracteres = 30000;
    private const int Muestras = 64;
    /// <summary>Distancia media (en radios) a la que la similitud llega a 0.</summary>
    private const double EscalaDistancia = 0.6;

    /// <summary>Lee los trazos; null con el mensaje para el técnico si no son válidos.</summary>
    public static (List<List<(double X, double Y)>>? Trazos, string? Error) Leer(string? json)
    {
        const string invalida = "La firma no es válida. Vuelve a dibujarla.";
        if (string.IsNullOrWhiteSpace(json) || json.Length > MaxCaracteres) return (null, invalida);
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Object || !doc.RootElement.TryGetProperty("trazos", out var raiz) || raiz.ValueKind != JsonValueKind.Array) return (null, invalida);
            var lista = new List<List<(double, double)>>();
            var total = 0;
            foreach (var t in raiz.EnumerateArray())
            {
                if (t.ValueKind != JsonValueKind.Array || lista.Count >= MaxTrazos) return (null, invalida);
                var puntos = new List<(double, double)>();
                foreach (var p in t.EnumerateArray())
                {
                    if (p.ValueKind != JsonValueKind.Array || p.GetArrayLength() != 2) return (null, invalida);
                    if (!p[0].TryGetDouble(out var x) || !p[1].TryGetDouble(out var y) || !double.IsFinite(x) || !double.IsFinite(y) || x is < 0 or > 1 || y is < 0 or > 1) return (null, invalida);
                    if (++total > MaxPuntos) return (null, invalida);
                    puntos.Add((x, y));
                }
                if (puntos.Count > 0) lista.Add(puntos);
            }
            if (total < MinPuntos) return (null, "La firma es demasiado corta. Dibújala completa.");
            var xs = lista.SelectMany(t => t).Select(p => p.Item1).ToList();
            var ys = lista.SelectMany(t => t).Select(p => p.Item2).ToList();
            if (Math.Max(xs.Max() - xs.Min(), ys.Max() - ys.Min()) < 0.08) return (null, "La firma es demasiado pequeña. Dibújala más grande.");
            return (lista, null);
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            return (null, invalida);
        }
    }

    /// <summary>Remuestrea el recorrido a N puntos por longitud de arco (los saltos entre trazos no suman distancia), centrado y de radio 1.</summary>
    internal static (double X, double Y)[] Normalizar(List<List<(double X, double Y)>> trazos)
    {
        var camino = new List<(double X, double Y, double S)>();
        double s = 0;
        foreach (var t in trazos)
            for (var i = 0; i < t.Count; i++)
            {
                if (i > 0) s += Math.Sqrt(Math.Pow(t[i].X - t[i - 1].X, 2) + Math.Pow(t[i].Y - t[i - 1].Y, 2));
                camino.Add((t[i].X, t[i].Y, s));
            }
        var res = new (double X, double Y)[Muestras];
        if (s <= 0) return res;
        var j = 0;
        for (var k = 0; k < Muestras; k++)
        {
            var objetivo = s * k / (Muestras - 1);
            while (j < camino.Count - 2 && camino[j + 1].S < objetivo) j++;
            var a = camino[j]; var b = camino[Math.Min(j + 1, camino.Count - 1)];
            var tramo = b.S - a.S;
            var f = tramo <= 1e-12 ? 0 : Math.Clamp((objetivo - a.S) / tramo, 0, 1);
            res[k] = (a.X + (b.X - a.X) * f, a.Y + (b.Y - a.Y) * f);
        }
        var cx = res.Average(p => p.X); var cy = res.Average(p => p.Y);
        var radio = Math.Sqrt(res.Average(p => Math.Pow(p.X - cx, 2) + Math.Pow(p.Y - cy, 2)));
        if (radio < 1e-9) radio = 1;
        for (var k = 0; k < Muestras; k++) res[k] = ((res[k].X - cx) / radio, (res[k].Y - cy) / radio);
        return res;
    }

    /// <summary>Similitud de 0 a 100 entre dos firmas ya leídas.</summary>
    public static double Similitud(List<List<(double X, double Y)>> a, List<List<(double X, double Y)>> b)
    {
        var na = Normalizar(a); var nb = Normalizar(b);
        double suma = 0;
        for (var k = 0; k < Muestras; k++) suma += Math.Sqrt(Math.Pow(na[k].X - nb[k].X, 2) + Math.Pow(na[k].Y - nb[k].Y, 2));
        var d = suma / Muestras;
        return Math.Round(Math.Clamp(1 - d / EscalaDistancia, 0, 1) * 100, 1, MidpointRounding.AwayFromZero);
    }

    /// <summary>Similitud entre dos firmas en JSON; 0 si alguna no se puede leer.</summary>
    public static double Similitud(string jsonA, string jsonB)
    {
        var a = Leer(jsonA).Trazos; var b = Leer(jsonB).Trazos;
        return a is null || b is null ? 0 : Similitud(a, b);
    }

    /// <summary>La firma más parecida de la lista (nombre y %), o null si no hay con qué comparar.</summary>
    public static (string Nombre, double Pct)? MasParecida(string trazos, IEnumerable<(string Nombre, string Trazos)> otras)
    {
        (string, double)? mejor = null;
        foreach (var (nombre, t) in otras)
        {
            var p = Similitud(trazos, t);
            if (mejor is null || p > mejor.Value.Item2) mejor = (nombre, p);
        }
        return mejor;
    }

    /// <summary>Texto del rechazo: igual al de la maqueta.</summary>
    public static string MensajeRechazo(string nombre, double pct) =>
        $"La firma no corresponde a este responsable: coincide en un {pct.ToString("0.#", CultureInfo.InvariantCulture)} % con la firma de {nombre}. Cada responsable debe firmar con su propia firma.";
}
