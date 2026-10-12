using System.Security.Cryptography;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// Contraseña temporal de 12 caracteres que cumple la política TW-SEC
/// (mayúscula, minúscula, número y símbolo). Usa un generador criptográfico.
/// Sin caracteres ambiguos (0/O, 1/l/I) para que se pueda dictar o copiar sin errores.
/// </summary>
public static class GeneradorContrasenaTemporal
{
    private const string Mayusculas = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    private const string Minusculas = "abcdefghijkmnpqrstuvwxyz";
    private const string Numeros    = "23456789";
    private const string Simbolos   = "!@#$%&*";

    public static string Generar(int longitud = 12)
    {
        if (longitud < 8) longitud = 8;
        string todos = Mayusculas + Minusculas + Numeros + Simbolos;

        var caracteres = new List<char>
        {
            Elegir(Mayusculas), Elegir(Minusculas), Elegir(Numeros), Elegir(Simbolos),
        };
        while (caracteres.Count < longitud) caracteres.Add(Elegir(todos));

        // Mezcla Fisher-Yates para que los 4 obligatorios no queden siempre al inicio.
        for (int i = caracteres.Count - 1; i > 0; i--)
        {
            int j = RandomNumberGenerator.GetInt32(i + 1);
            (caracteres[i], caracteres[j]) = (caracteres[j], caracteres[i]);
        }
        return new string(caracteres.ToArray());
    }

    private static char Elegir(string fuente) => fuente[RandomNumberGenerator.GetInt32(fuente.Length)];
}
