using System.Globalization;
using System.Text;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// Comparación aproximada de textos para evitar duplicados (ticket #4290).
/// Detecta variantes de escritura como las que mencionó TW en la reunión:
/// "Controlador de temperatura" ≈ "controlador de temp." ≈ "CTRL de temperatura" ≈ "Controlador de T.".
/// Ignora mayúsculas, tildes, puntos y espacios repetidos.
/// </summary>
public static class Similitud
{
    /// <summary>Puntaje de 0 a 100. 100 = mismo texto normalizado.</summary>
    public static int Puntaje(string escrito, string existente)
    {
        var a = Normalizar(escrito);
        var b = Normalizar(existente);
        if (a.Length == 0 || b.Length == 0) return 0;
        if (a == b) return 100;

        var lev = (int)Math.Round(100.0 * (1 - (double)Levenshtein(a, b) / Math.Max(a.Length, b.Length)));
        var puntaje = Math.Max(Math.Max(lev, PuntajePorPalabras(a, b)), PuntajePorInclusion(a, b));

        // "Área 4" y "Área 5" son cosas distintas: si los números no coinciden, no son parecidos.
        return Numeros(a) == Numeros(b) ? puntaje : Math.Min(puntaje, 50);
    }

    /// <summary>85 o más: probable duplicado.</summary>
    public const int UmbralDuplicado = 85;
    /// <summary>70 a 84: parecido (se muestra como referencia).</summary>
    public const int UmbralParecido  = 70;

    private static readonly HashSet<string> PalabrasVacias =
        ["de", "del", "la", "las", "el", "los", "y", "e", "o", "u", "a", "en", "con", "para", "por", "sin", "al"];

    private static string Numeros(string t) => string.Join(' ', t.Split(' ').Where(p => p.Any(char.IsDigit)));

    /// <summary>Minúsculas, sin tildes ni signos, espacios simples.</summary>
    public static string Normalizar(string texto)
    {
        var sb = new StringBuilder();
        foreach (var c in (texto ?? "").Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(char.IsLetterOrDigit(c) ? char.ToLowerInvariant(c) : ' ');
        }
        return string.Join(' ', sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    // Cada palabra escrita debe "calzar" con una palabra del existente: igual, prefijo
    // ("temp" → "temperatura", "t" → "temperatura") o abreviatura por consonantes ("ctrl" → "controlador").
    private static int PuntajePorPalabras(string a, string b)
    {
        var pa = a.Split(' '); var pb = b.Split(' ').ToList();
        if (pa.Length != pb.Count) return 0;
        double total = 0;
        for (int i = 0; i < pa.Length; i++)
        {
            string x = pa[i], y = pb[i];
            if (x == y) total += 1;
            else if (y.StartsWith(x)) total += x.Length >= 3 ? 0.9 : 0.75;
            else if (x.StartsWith(y)) total += y.Length >= 3 ? 0.9 : 0.75;
            else if (EsAbreviatura(x, y) || EsAbreviatura(y, x)) total += 0.85;
            else return 0;
        }
        return (int)Math.Round(100 * total / pa.Length);
    }

    // Uno de los textos está contenido en el otro, palabra por palabra y en orden:
    // "Mettler" ⊂ "Mettler Toledo", "Controlador" ⊂ "Controlador de temperatura".
    // Puntaje 75 a 95 según qué parte del texto largo cubre el corto.
    private static int PuntajePorInclusion(string a, string b)
    {
        var corta = a.Split(' '); var larga = b.Split(' ');
        if (corta.Length > larga.Length) (corta, larga) = (larga, corta);
        if (corta.Length == larga.Length) return 0;

        // "de", "la", "para"... solas no identifican nada.
        if (corta.All(p => p.Length < 3 || PalabrasVacias.Contains(p))) return 0;

        int j = 0;
        foreach (var palabra in larga)
            if (j < corta.Length && (palabra == corta[j] || (corta[j].Length >= 3 && palabra.StartsWith(corta[j])))) j++;
        if (j < corta.Length) return 0;

        return (int)Math.Round(75 + 20.0 * corta.Length / larga.Length);
    }

    // "ctrl" es abreviatura de "controlador": misma primera letra y sus letras aparecen en orden.
    private static bool EsAbreviatura(string corta, string larga)
    {
        if (corta.Length < 3 || corta.Length >= larga.Length || corta[0] != larga[0]) return false;
        int j = 0;
        foreach (var c in larga) if (j < corta.Length && c == corta[j]) j++;
        return j == corta.Length;
    }

    private static int Levenshtein(string a, string b)
    {
        var d = new int[b.Length + 1];
        for (int j = 0; j <= b.Length; j++) d[j] = j;
        for (int i = 1; i <= a.Length; i++)
        {
            int prev = d[0]; d[0] = i;
            for (int j = 1; j <= b.Length; j++)
            {
                int tmp = d[j];
                d[j] = Math.Min(Math.Min(d[j] + 1, d[j - 1] + 1), prev + (a[i - 1] == b[j - 1] ? 0 : 1));
                prev = tmp;
            }
        }
        return d[b.Length];
    }
}
