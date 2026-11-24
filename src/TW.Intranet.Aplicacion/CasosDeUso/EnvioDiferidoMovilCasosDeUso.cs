using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// App móvil sin señal — reglas puras de la constancia de envíos tardíos. La app manda, en un reenvío de su cola, tres cabeceras:
/// X-TW-Capturado-En (ISO 8601: cuándo lo tomó el técnico), X-TW-Motivo-Envio (sin_senal · servidor_no_disponible) y X-TW-Intentos (cuántas veces lo intentó).
/// </summary>
public static class ReglasEnvioDiferido
{
    public const string CabeceraCapturadoEn = "X-TW-Capturado-En";
    public const string CabeceraMotivo      = "X-TW-Motivo-Envio";
    public const string CabeceraIntentos    = "X-TW-Intentos";

    /// <summary>Lee la hora de captura de la cabecera y la devuelve en UTC; texto vacío o ilegible = no es un envío tardío.</summary>
    public static bool TryLeerCaptura(string? valor, out DateTime capturadoUtc)
    {
        capturadoUtc = default;
        if (string.IsNullOrWhiteSpace(valor) || valor.Length > 40) return false;
        if (!DateTimeOffset.TryParse(valor, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var t)) return false;
        capturadoUtc = t.UtcDateTime;
        return true;
    }

    /// <summary>Intentos de la cabecera, acotados de 0 a 99; ilegible = 0.</summary>
    public static int LeerIntentos(string? valor) =>
        int.TryParse(valor, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? Math.Clamp(n, 0, 99) : 0;

    /// <summary>Solo los métodos que escriben dejan constancia.</summary>
    public static bool EsEscritura(string? metodo) =>
        string.Equals(metodo, "POST", StringComparison.OrdinalIgnoreCase)
        || string.Equals(metodo, "PUT", StringComparison.OrdinalIgnoreCase)
        || string.Equals(metodo, "DELETE", StringComparison.OrdinalIgnoreCase);
}

/// <summary>Deja constancia de un registro de campo enviado tarde. No cambia el registro original ni rechaza nada.</summary>
public class RegistrarEnvioDiferidoMovilCasoDeUso(IEnvioDiferidoMovilRepositorio repo)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        long idUsuario, string metodo, string ruta, long? idOs, long? idOsEquipo, DateTime capturadoUtc, string? motivo, int intentos, CancellationToken ct) =>
        repo.RegistrarAsync(idUsuario, metodo, ruta, idOs, idOsEquipo, capturadoUtc, motivo, intentos, ct);
}

/// <summary>Los registros que la app envió tarde de un servicio (o de un equipo), para Jefatura y la intranet.</summary>
public class ListarEnviosDiferidosMovilCasoDeUso(IEnvioDiferidoMovilRepositorio repo)
{
    public Task<RespuestaDto<IReadOnlyList<EnvioDiferidoDto>>> EjecutarAsync(long idOs, long? idOsEquipo, CancellationToken ct) =>
        repo.ListarAsync(idOs, idOsEquipo, ct);
}
