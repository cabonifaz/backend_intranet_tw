using System.Globalization;
using System.Text;
using TW.Intranet.Aplicacion.Puertos;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Comprueba que el fragmento que citó la IA exista de verdad en el PDF oficial (la defensa contra citas inventadas). Se busca en la página citada y en las dos vecinas
/// (la IA puede contar las páginas distinto al número impreso); sin página se recorren hasta 80 páginas.
///  - Se compara sin mayúsculas, sin acentos y sin signos: solo importan las palabras y su orden.
///  - Coincidencia exacta = la secuencia completa de palabras del fragmento está en la página → verificada = true y se devuelve lo que sigue en la página.
///  - Coincidencia parcial = al menos el 80 % de las tríadas de palabras del fragmento están en la página (la IA a veces omite una palabra) → true, sin contexto.
///  - Ninguna → false. PDF sin texto (escaneado) o ilegible → null: no se puede comprobar.
/// </summary>
public static class VerificadorCitasPdf
{
    public const int MaxPaginasSinPagina = 80;
    public const int MaxContextoPosterior = 400;
    public const double UmbralParcial = 0.8;
    private const int MinPalabrasParcial = 6;

    /// <summary>Palabras normalizadas: minúsculas, sin acentos y solo letras y números.</summary>
    public static List<string> Tokens(string? texto)
    {
        var lista = new List<string>();
        if (string.IsNullOrWhiteSpace(texto)) return lista;
        var actual = new StringBuilder();
        foreach (var c in texto.Normalize(NormalizationForm.FormD))
        {
            var cat = CharUnicodeInfo.GetUnicodeCategory(c);
            if (cat == UnicodeCategory.NonSpacingMark) continue;
            if (char.IsLetterOrDigit(c)) actual.Append(char.ToLowerInvariant(c));
            else if (actual.Length > 0) { lista.Add(actual.ToString()); actual.Clear(); }
        }
        if (actual.Length > 0) lista.Add(actual.ToString());
        return lista;
    }

    /// <summary>Busca el fragmento entre las palabras de una página. Sin texto en la página: (null, null).</summary>
    public static (bool? Encontrado, string? Posterior) BuscarEnPagina(IReadOnlyList<string> palabrasPagina, IReadOnlyList<string> fragmento)
    {
        // Cada palabra original puede dar varios tokens ("6.4" → "6", "4"); se recuerda a qué palabra pertenece cada uno
        var tokens = new List<string>();
        var origen = new List<int>();
        for (var i = 0; i < palabrasPagina.Count; i++)
            foreach (var t in Tokens(palabrasPagina[i])) { tokens.Add(t); origen.Add(i); }
        if (tokens.Count == 0) return (null, null);

        var f = fragmento.SelectMany(p => Tokens(p)).ToList();
        if (f.Count == 0) return (false, null);

        // Coincidencia exacta: toda la secuencia, seguida
        for (var i = 0; i + f.Count <= tokens.Count; i++)
        {
            if (tokens[i] != f[0]) continue;
            var ok = true;
            for (var k = 1; k < f.Count && ok; k++) ok = tokens[i + k] == f[k];
            if (!ok) continue;
            var fin = origen[i + f.Count - 1];
            return (true, Posterior(palabrasPagina, fin + 1));
        }

        // Coincidencia parcial: tríadas de palabras
        if (f.Count < MinPalabrasParcial) return (false, null);
        var triadasPagina = new HashSet<string>();
        for (var i = 0; i + 3 <= tokens.Count; i++) triadasPagina.Add($"{tokens[i]} {tokens[i + 1]} {tokens[i + 2]}");
        var total = f.Count - 2;
        var presentes = 0;
        for (var i = 0; i + 3 <= f.Count; i++)
            if (triadasPagina.Contains($"{f[i]} {f[i + 1]} {f[i + 2]}")) presentes++;
        return ((double)presentes / total >= UmbralParcial, null);
    }

    /// <summary>Hasta 400 caracteres de lo que sigue en la página, cortados entre palabras; null si no hay nada más.</summary>
    private static string? Posterior(IReadOnlyList<string> palabras, int desde)
    {
        var sb = new StringBuilder();
        for (var i = desde; i < palabras.Count; i++)
        {
            if (sb.Length + palabras[i].Length + 1 > MaxContextoPosterior) { sb.Append('…'); break; }
            if (sb.Length > 0) sb.Append(' ');
            sb.Append(palabras[i]);
        }
        var s = sb.ToString().Trim();
        return s.Length == 0 ? null : s;
    }

    /// <summary>
    /// Recorre las páginas candidatas (la citada primero, luego sus vecinas) y devuelve el primer resultado verdadero; false si en ninguna está y alguna tenía texto;
    /// null si ninguna tenía texto o el PDF no se pudo leer.
    /// </summary>
    public static VerificacionCitaAsistente Verificar(byte[] pdf, int? pagina, string fragmento)
    {
        try
        {
            using var doc = PdfDocument.Open(pdf);
            var n = doc.NumberOfPages;
            if (n == 0) return new VerificacionCitaAsistente(null, null);

            IEnumerable<int> candidatas = pagina is > 0
                ? new[] { pagina.Value, pagina.Value - 1, pagina.Value + 1 }.Where(p => p >= 1 && p <= n).Distinct()
                : Enumerable.Range(1, Math.Min(n, MaxPaginasSinPagina));

            var frag = fragmento.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            var conTexto = false;
            foreach (var p in candidatas)
            {
                var texto = ContentOrderTextExtractor.GetText(doc.GetPage(p));
                var palabras = texto.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                var (encontrado, posterior) = BuscarEnPagina(palabras, frag);
                if (encontrado is null) continue;
                conTexto = true;
                if (encontrado == true) return new VerificacionCitaAsistente(true, posterior);
            }
            return new VerificacionCitaAsistente(conTexto ? false : null, null);
        }
        catch (Exception)
        {
            // PDF dañado, protegido o con una estructura que PdfPig no entiende: no se puede comprobar
            return new VerificacionCitaAsistente(null, null);
        }
    }
}
