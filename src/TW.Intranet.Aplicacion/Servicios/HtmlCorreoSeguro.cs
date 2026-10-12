using System.Net;
using System.Text.RegularExpressions;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// HU-19 — Limpieza del HTML del editor de texto enriquecido antes de enviarlo por correo,
/// y versión en texto plano (para el correo y para las notas del seguimiento).
/// </summary>
public static partial class HtmlCorreoSeguro
{
    [GeneratedRegex(@"<\s*(script|style|iframe|object|embed|form|input|button|meta|link|base)\b[^>]*>.*?<\s*/\s*\1\s*>",
                    RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex BloquesPeligrosos();

    [GeneratedRegex(@"<\s*/?\s*(script|style|iframe|object|embed|form|input|button|meta|link|base)\b[^>]*>",
                    RegexOptions.IgnoreCase)]
    private static partial Regex EtiquetasPeligrosas();

    [GeneratedRegex(@"\s+on[a-z]+\s*=\s*(""[^""]*""|'[^']*'|[^\s>]+)", RegexOptions.IgnoreCase)]
    private static partial Regex AtributosEvento();

    [GeneratedRegex(@"(href|src)\s*=\s*([""']?)\s*(javascript|vbscript|data)\s*:", RegexOptions.IgnoreCase)]
    private static partial Regex EnlacesPeligrosos();

    [GeneratedRegex(@"<\s*br\s*/?\s*>|<\s*/\s*(p|div|li|h[1-6]|tr)\s*>", RegexOptions.IgnoreCase)]
    private static partial Regex SaltosDeLinea();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex Etiquetas();

    [GeneratedRegex(@"[ \t]+")]
    private static partial Regex Espacios();

    [GeneratedRegex(@"\n{3,}")]
    private static partial Regex LineasVacias();

    /// <summary>Quita scripts, iframes, formularios, eventos on* y enlaces javascript:/data:.</summary>
    public static string Limpiar(string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) return "";
        var limpio = BloquesPeligrosos().Replace(html, "");
        limpio = EtiquetasPeligrosas().Replace(limpio, "");
        limpio = AtributosEvento().Replace(limpio, "");
        limpio = EnlacesPeligrosos().Replace(limpio, "$1=$2#");
        return limpio.Trim();
    }

    /// <summary>Texto plano: saltos de línea por párrafos y &lt;br&gt;, sin etiquetas.</summary>
    public static string ATexto(string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) return "";
        var texto = SaltosDeLinea().Replace(html, "\n");
        texto = Etiquetas().Replace(texto, "");
        texto = WebUtility.HtmlDecode(texto).Replace("\r", "");
        texto = Espacios().Replace(texto, " ");
        texto = string.Join('\n', texto.Split('\n').Select(l => l.Trim()));
        return LineasVacias().Replace(texto, "\n\n").Trim();
    }
}
