using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// App Mobile HU-20 — Reloj marcador de jornada. El usuario sale siempre del token; el orden, la hora, la puntualidad y el GPS los vuelve a validar el SP.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// <summary>La jornada de hoy del técnico: estado, paso habilitado, horario programado, marcaciones y resumen.</summary>
public class ObtenerJornadaMovilCasoDeUso(IJornadaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<JornadaMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<JornadaMovilDto>(1, "Usuario no válido."))
            : repositorio.ObtenerAsync(idUsuario, ct);
}

/// <summary>Marca un paso de la jornada (también las guardadas sin conexión, con la hora del teléfono).</summary>
public class MarcarJornadaMovilCasoDeUso(IJornadaMovilRepositorio repositorio)
{
    private static readonly string[] Tipos = ["inicio_labores", "inicio_refrigerio", "fin_refrigerio", "salida_planta", "fin_labores"];

    public Task<RespuestaDto<MarcacionRegistradaDto>> EjecutarAsync(long idUsuario, MarcarJornadaDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<MarcacionRegistradaDto>(1, "Usuario no válido."));
        var tipo = d?.Tipo?.Trim().ToLowerInvariant();
        if (tipo is null || !Tipos.Contains(tipo)) return Task.FromResult(new RespuestaDto<MarcacionRegistradaDto>(1, "La marcación no es válida."));
        if (d!.Latitud is not { } lat || d.Longitud is not { } lon || lat is < -90m or > 90m || lon is < -180m or > 180m || (lat == 0m && lon == 0m))
            return Task.FromResult(new RespuestaDto<MarcacionRegistradaDto>(1, "No se pudo tomar tu ubicación. Activa el GPS e inténtalo de nuevo."));
        if (d.PrecisionMetros is < 0m or > 5000m)
            return Task.FromResult(new RespuestaDto<MarcacionRegistradaDto>(1, "La precisión de la ubicación no es válida."));

        DateTime? marcado = null;
        if (!string.IsNullOrWhiteSpace(d.MarcadoEn))
        {
            if (d.MarcadoEn.Length > 40 || !DateTimeOffset.TryParse(d.MarcadoEn, CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var x))
                return Task.FromResult(new RespuestaDto<MarcacionRegistradaDto>(1, "La hora de la marcación no es válida."));
            marcado = DateTime.SpecifyKind(x.UtcDateTime, DateTimeKind.Unspecified);
        }
        return repositorio.MarcarAsync(idUsuario, tipo, Math.Round(lat, 7), Math.Round(lon, 7), d.PrecisionMetros is { } p ? Math.Round(p, 1) : null, marcado, d.SinConexion, ct);
    }
}

/// <summary>Posición GPS del técnico con la jornada en curso (no exige un servicio en curso). Mismas validaciones que la de un servicio (HU-51).</summary>
public class RegistrarUbicacionJornadaMovilCasoDeUso(IJornadaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<UbicacionRegistradaDto>> EjecutarAsync(long idUsuario, RegistrarUbicacionDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<UbicacionRegistradaDto>(1, "Usuario no válido."));
        if (d?.Latitud is not { } lat || d.Longitud is not { } lon || lat is < -90m or > 90m || lon is < -180m or > 180m || (lat == 0m && lon == 0m))
            return Task.FromResult(new RespuestaDto<UbicacionRegistradaDto>(1, "La ubicación no es válida."));
        if (d.PrecisionMetros is < 0m or > 5000m)
            return Task.FromResult(new RespuestaDto<UbicacionRegistradaDto>(1, "La precisión de la ubicación no es válida."));
        decimal? velocidad = d.VelocidadKmh is >= 0m and <= 400m ? Math.Round(d.VelocidadKmh.Value, 1) : null;
        decimal? altitud   = d.AltitudM is >= -500m and <= 9000m ? Math.Round(d.AltitudM.Value, 1) : null;
        return repositorio.RegistrarUbicacionAsync(idUsuario, Math.Round(lat, 7), Math.Round(lon, 7), d.PrecisionMetros is { } p ? Math.Round(p, 1) : null, velocidad, altitud, ct);
    }
}
