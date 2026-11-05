using System.Text.RegularExpressions;

namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// #4437 — Código de la propuesta para mostrar: "PC: 0012-2-2026" (prefijo · correlativo de 4 dígitos · versión · año).
/// En BD el número sigue igual (PROP-000012): agrupa las versiones y lo referencian OS, OC, expedientes y búsquedas.
/// El año es el de creación de la versión.
/// </summary>
public static partial class FormatoNumeroPropuesta
{
    [GeneratedRegex(@"(\d+)\s*$")]
    private static partial Regex Correlativo();

    public static string Formatear(string? numero, int version, DateTime? fechaCreacion)
    {
        if (string.IsNullOrWhiteSpace(numero)) return "";
        var m = Correlativo().Match(numero);
        if (!m.Success) return numero;
        var correlativo = long.TryParse(m.Groups[1].Value, out var n) ? n.ToString("0000") : m.Groups[1].Value;
        var anio = (fechaCreacion ?? DateTime.Now).Year;
        return $"PC: {correlativo}-{Math.Max(version, 1)}-{anio}";
    }
}
