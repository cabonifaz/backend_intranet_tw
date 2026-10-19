namespace TW.Intranet.Dominio.Valores;

/// <summary>
/// Reglas del RUC peruano: 11 dígitos, prefijo válido (10, 15, 16, 17, 20)
/// y dígito verificador módulo 11 (mismo cálculo que SUNAT).
/// </summary>
public static class ValidadorRuc
{
    private static readonly int[] Factores = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    private static readonly string[] PrefijosValidos = ["10", "15", "16", "17", "20"];

    /// <summary>Quita espacios y guiones. No valida.</summary>
    public static string Normalizar(string? ruc) =>
        new((ruc ?? "").Where(char.IsDigit).ToArray());

    public static bool TieneFormato(string ruc) =>
        ruc.Length == 11 && ruc.All(char.IsDigit);

    public static bool TienePrefijoValido(string ruc) =>
        PrefijosValidos.Any(ruc.StartsWith);

    public static bool DigitoVerificadorCorrecto(string ruc)
    {
        if (!TieneFormato(ruc)) return false;
        int suma = 0;
        for (int i = 0; i < 10; i++) suma += Factores[i] * (ruc[i] - '0');
        int residuo = 11 - (suma % 11);
        int digito  = residuo == 10 ? 0 : residuo == 11 ? 1 : residuo;
        return digito == ruc[10] - '0';
    }

    /// <summary>true si es RUC de persona jurídica (empresa).</summary>
    public static bool EsPersonaJuridica(string ruc) => ruc.StartsWith("20");
}
