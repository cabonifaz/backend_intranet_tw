using System.Globalization;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-10 — Ensayos y Calibración ───────────────────────────────────────────────────

/// <summary>Lecturas, límites y formas del plato: la validación de forma (el SP vuelve a validar y calcula error, EMP y conformidad).</summary>
public static class EntradaEnsayosMovil
{
    public const int MaxCargasPesaje = 12;
    public const int MaxCargasExcentricidad = 10;
    public const decimal MaxValor = 100_000_000m;
    public static readonly IReadOnlySet<string> Formas = new HashSet<string> { "rectangular", "circular", "triangular" };

    /// <summary>Posiciones de excentricidad según la forma del plato (la 1 es el centro).</summary>
    public static int Posiciones(string forma) => forma == "triangular" ? 4 : 5;

    /// <summary>Valida lo que llega; null si está bien, o el mensaje para el técnico.</summary>
    public static string? Validar(GuardarEnsayosMovilDto? d)
    {
        if (d is null) return "Datos incompletos.";
        if (!Formas.Contains((d.FormaPlato ?? "rectangular").Trim().ToLowerInvariant())) return "La forma del plato no es válida.";
        var pesaje = d.Pesaje ?? [];
        var ecc = d.Excentricidad ?? [];
        if (pesaje.Count == 0 && ecc.Count == 0) return "No hay lecturas para guardar.";
        if (pesaje.Count > MaxCargasPesaje) return $"No se aceptan más de {MaxCargasPesaje} cargas de pesaje.";
        if (ecc.Count > MaxCargasExcentricidad) return $"No se aceptan más de {MaxCargasExcentricidad} cargas de excentricidad.";

        static bool CargaOk(decimal? c) => c is > 0 and <= MaxValor;
        static bool IndOk(decimal? i) => i is null || i is >= 0 and <= MaxValor;
        if (pesaje.Any(p => !CargaOk(p.Carga) || !IndOk(p.Indicacion))) return "Revisa el pesaje: cada carga debe ser mayor que 0 y las indicaciones no pueden ser negativas.";

        var max = Posiciones((d.FormaPlato ?? "rectangular").Trim().ToLowerInvariant());
        if (ecc.Any(c => !CargaOk(c.Carga) || (c.Lecturas?.Count ?? 0) > max || (c.Lecturas ?? []).Any(i => !IndOk(i))))
            return "Revisa la excentricidad: cada carga debe ser mayor que 0, sin indicaciones negativas y con las posiciones del plato.";

        var motivo = EntradaObjetivosMovil.Limpiar(d.MotivoErrorCritico);
        if (motivo is not null && (motivo.Length < 3 || motivo.Length > 300)) return "El motivo debe tener entre 3 y 300 caracteres.";
        return null;
    }

    /// <summary>JSON que recibe el SP: solo carga e indicación, con punto decimal (no depende de la cultura del servidor).</summary>
    public static string ArmarJson(GuardarEnsayosMovilDto d)
    {
        object? N(decimal? v) => v is null ? null : Math.Round(v.Value, 4);
        var cuerpo = new
        {
            pesaje = (d.Pesaje ?? []).Select(p => new { carga = N(p.Carga), indicacion = N(p.Indicacion) }),
            excentricidad = (d.Excentricidad ?? []).Select(c => new { carga = N(c.Carga), lecturas = (c.Lecturas ?? []).Select(N) }),
        };
        return JsonSerializer.Serialize(cuerpo, new JsonSerializerOptions { NumberHandling = System.Text.Json.Serialization.JsonNumberHandling.Strict });
    }
}

/// <summary>Pantalla de Ensayos: especificaciones del equipo, lecturas guardadas (con error, EMP y conformidad) y a quién llamar.</summary>
public class ObtenerEnsayosMovilCasoDeUso(IEnsayosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<EnsayosMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<EnsayosMovilDto>(1, "Servicio o equipo no encontrado."))
            : repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
}

/// <summary>
/// Guarda (o finaliza) los ensayos. El servidor calcula error, EMP y conformidad; el motivo de "Guardar de todas formas" se guarda y avisa al encargado.
/// Devuelve los ensayos ya actualizados para que la app los pinte sin otra consulta.
/// </summary>
public class GuardarEnsayosMovilCasoDeUso(IEnsayosMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<EnsayosMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, GuardarEnsayosMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Servicio o equipo no encontrado.");
        if (EntradaEnsayosMovil.Validar(d) is { } error) return new(1, error);

        var forma = (d!.FormaPlato ?? "rectangular").Trim().ToLowerInvariant();
        var r = await repositorio.GuardarAsync(idUsuario, idOs, idOsEquipo, forma, EntradaEnsayosMovil.ArmarJson(d),
            EntradaObjetivosMovil.Limpiar(d.MotivoErrorCritico), d.Finalizar, ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);

        var ensayos = await repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
        return new(2, r.Mensaje, ensayos.IdTipoMensaje == 2 ? ensayos.Datos : null);
    }
}

/// <summary>Registra la llamada al encargado del área en el ensayo (hora y error reportado) y devuelve a quién llamar.</summary>
public class RegistrarLlamadaEnsayoMovilCasoDeUso(IEnsayosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ResultadoLlamadaEnsayoMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, PeticionLlamadaEnsayoMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0)
            return Task.FromResult(new RespuestaDto<ResultadoLlamadaEnsayoMovilDto>(1, "Servicio o equipo no encontrado."));
        var detalle = EntradaObjetivosMovil.Limpiar(d?.Detalle);
        if (detalle is { Length: > 300 })
            return Task.FromResult(new RespuestaDto<ResultadoLlamadaEnsayoMovilDto>(1, "El detalle puede tener hasta 300 caracteres."));
        return repositorio.RegistrarLlamadaAsync(idUsuario, idOs, idOsEquipo, detalle, ct);
    }
}
