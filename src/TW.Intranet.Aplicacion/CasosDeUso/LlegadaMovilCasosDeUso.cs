using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-06 — Registro de llegada y Hard Stop ─────────────────────────────────────────

/// <summary>Validación común de la ubicación que envía la app (la distancia y la precisión máxima las evalúa el SP).</summary>
public static class EntradaLlegadaMovil
{
    public const string SinServicio = "Servicio no encontrado o no asignado a tu usuario.";

    /// <summary>Valida el GPS; devuelve el mensaje para el técnico o null si está bien.</summary>
    public static string? Validar(PeticionLlegadaMovilDto? d) =>
        d?.Latitud is not { } lat || d.Longitud is not { } lon || lat is < -90m or > 90m || lon is < -180m or > 180m || (lat == 0m && lon == 0m)
            ? "La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo."
            : d.PrecisionMetros is not { } p || p < 0m || p > 5000m
                ? "La precisión del GPS no es válida."
                : null;
}

/// <summary>Contexto de "Registrar llegada": planta esperada, radio permitido, hora programada y la llegada ya registrada.</summary>
public class ObtenerLlegadaMovilCasoDeUso(ILlegadaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<LlegadaMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0
            ? Task.FromResult(new RespuestaDto<LlegadaMovilDto>(1, EntradaLlegadaMovil.SinServicio))
            : repositorio.ObtenerAsync(idUsuario, idOs, ct);
}

/// <summary>Compara la ubicación con la planta sin registrar nada (la app lo pide cada vez que captura el GPS).</summary>
public class ValidarLlegadaMovilCasoDeUso(ILlegadaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ValidacionLlegadaMovilDto>> EjecutarAsync(long idUsuario, long idOs, PeticionLlegadaMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return Task.FromResult(new RespuestaDto<ValidacionLlegadaMovilDto>(1, EntradaLlegadaMovil.SinServicio));
        if (EntradaLlegadaMovil.Validar(d) is { } error) return Task.FromResult(new RespuestaDto<ValidacionLlegadaMovilDto>(1, error));
        return repositorio.ValidarAsync(idUsuario, idOs, Math.Round(d!.Latitud!.Value, 7), Math.Round(d.Longitud!.Value, 7), Math.Round(d.PrecisionMetros!.Value, 1), ct);
    }
}

/// <summary>
/// El técnico confirma su llegada. El usuario sale del token y la OS debe ser suya; el SP vuelve a evaluar la ubicación (Hard Stop: fuera del radio
/// permitido o con precisión baja no se registra), registra el evento LLEGADA con GPS y hora, y es idempotente por viaje.
/// </summary>
public class RegistrarLlegadaMovilCasoDeUso(ILlegadaMovilRepositorio repositorio)
{
    /// <summary>ISO 8601 con zona → UTC sin zona (como la guarda el SP); sin zona se toma como UTC. Inválido o muy largo → null (vale la hora del servidor).</summary>
    public static DateTime? CapturaUtc(string? texto) =>
        texto is { Length: > 0 and <= 40 }
        && DateTimeOffset.TryParse(texto, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var f)
            ? DateTime.SpecifyKind(f.UtcDateTime, DateTimeKind.Unspecified)
            : null;

    public Task<RespuestaDto<ResultadoLlegadaMovilDto>> EjecutarAsync(long idUsuario, long idOs, PeticionLlegadaMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return Task.FromResult(new RespuestaDto<ResultadoLlegadaMovilDto>(1, EntradaLlegadaMovil.SinServicio));
        if (EntradaLlegadaMovil.Validar(d) is { } error) return Task.FromResult(new RespuestaDto<ResultadoLlegadaMovilDto>(1, error));
        return repositorio.RegistrarAsync(idUsuario, idOs, Math.Round(d!.Latitud!.Value, 7), Math.Round(d.Longitud!.Value, 7),
            Math.Round(d.PrecisionMetros!.Value, 1), CapturaUtc(d.CapturadoEn), ct);
    }
}
