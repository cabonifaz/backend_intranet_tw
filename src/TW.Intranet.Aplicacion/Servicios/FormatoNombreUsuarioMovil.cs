using System.Text.RegularExpressions;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// Formato del usuario con el que una persona entra a la app móvil (App Mobile HU-01):
/// 4 a 30 caracteres, solo minúsculas, números, punto, guion o guion bajo. Nunca un correo.
/// Lo comparten la ficha de usuario, la asignación de acceso y la validación en línea.
/// </summary>
public static partial class FormatoNombreUsuarioMovil
{
    public const int MaxLongitud = 30;

    public const string MensajeFormato =
        "El usuario debe tener de 4 a 30 caracteres: letras minúsculas, números, punto, guion o guion bajo (sin espacios ni @).";

    [GeneratedRegex("^[a-z0-9._-]{4,30}$")]
    private static partial Regex Formato();

    /// <summary>Minúsculas y sin espacios en los extremos. Vacío si no se envió nada.</summary>
    public static string Normalizar(string? nombreUsuario)
        => (nombreUsuario ?? string.Empty).Trim().ToLowerInvariant();

    /// <summary>Recibe el texto ya normalizado.</summary>
    public static bool EsValido(string nombreUsuario) => Formato().IsMatch(nombreUsuario);
}
