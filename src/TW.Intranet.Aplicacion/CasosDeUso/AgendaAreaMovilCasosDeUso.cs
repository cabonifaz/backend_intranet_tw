using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-37 — Agenda y carga del área (Jefe de Área) ─────────────────────────────────────────────────────────────

/// <summary>
/// Validación de entrada de la agenda y de la resolución de conflictos. Desarrollo seguro: fechas y horas con formato estricto, opciones y tipos de una lista cerrada, ids positivos y comentario acotado.
/// El alcance del jefe, los permisos, la detección del conflicto, los cruces de horario, la SSOMA y el circuito directa / solicitud los valida el SP con las reglas de la intranet (HU-35 a HU-39).
/// </summary>
public static class ValidacionAgendaAreaMovil
{
    public const int MaxComentario = 400;
    public const int SemanasRango = 26;
    public static readonly string[] Tipos = ["baja", "ssoma_vencido", "solapamiento", "extension_duracion"];

    public const string MensajeFechaInvalida = "La fecha no es válida: usa el formato AAAA-MM-DD.";
    public const string MensajeFueraDeRango  = "La semana pedida está fuera del rango (hasta 26 semanas antes o después de la actual).";

    private static bool EsCruce(string tipo) => tipo is "solapamiento" or "extension_duracion";

    /// <summary>El lunes de la semana de una fecha.</summary>
    public static DateOnly Lunes(DateOnly fecha) => fecha.AddDays(-(((int)fecha.DayOfWeek + 6) % 7));

    /// <summary>Devuelve el error o el lunes normalizado «yyyy-MM-dd» (null = la semana actual, que resuelve el SP en hora de Lima). hoyLima = la fecha de hoy en Lima (UTC-5).</summary>
    public static (string? Error, string? Desde) NormalizarDesde(string? desde, DateOnly hoyLima)
    {
        var texto = (desde ?? string.Empty).Trim();
        if (texto.Length == 0) return (null, null);
        if (!DateOnly.TryParseExact(texto, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fecha)) return (MensajeFechaInvalida, null);

        var lunes = Lunes(fecha);
        if (Math.Abs(lunes.DayNumber - Lunes(hoyLima).DayNumber) > SemanasRango * 7) return (MensajeFueraDeRango, null);
        return (null, lunes.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
    }

    /// <summary>Validación del detalle de un conflicto (el mismo identificador que la resolución). Devuelve el error o los valores normalizados.</summary>
    public static (string? Error, string Tipo, long IdTecnico, long IdOsA, long? IdOsB) NormalizarConflicto(string? tipo, long? idTecnico, long? idOsA, long? idOsB)
    {
        static (string?, string, long, long, long?) Falla(string m) => (m, "", 0, 0, null);

        var t = (tipo ?? string.Empty).Trim().ToLowerInvariant();
        if (!Tipos.Contains(t)) return Falla("El tipo de conflicto no es válido.");
        if (idTecnico is not > 0 || idOsA is not > 0) return Falla("Indica el técnico y la orden del conflicto.");
        if (EsCruce(t))
        {
            if (idOsB is not > 0 || idOsB == idOsA) return Falla("Indica las dos órdenes que se cruzan.");
            return (null, t, idTecnico.Value, idOsA.Value, idOsB);
        }
        return (null, t, idTecnico.Value, idOsA.Value, null);   // baja y SSOMA: la segunda orden no aplica
    }

    /// <summary>Validación de «Resolver»: opción, técnico nuevo o nueva fecha y horario, motivo y comentario. Devuelve el error o los datos normalizados.</summary>
    public static (string? Error, ResolucionConflictoDatos? Datos) NormalizarResolucion(ResolverConflictoAgendaDto? d, DateOnly hoyLima)
    {
        if (d is null) return ("Indica cómo resolver el conflicto.", null);

        var c = NormalizarConflicto(d.Tipo, d.IdTecnico, d.IdOsA, d.IdOsB);
        if (c.Error is not null) return (c.Error, null);

        var opcion = (d.Opcion ?? string.Empty).Trim().ToLowerInvariant();
        if (opcion is not ("reasignar" or "reprogramar")) return ("Selecciona cómo resolver el conflicto: reasignar o reprogramar.", null);

        if (d.IdOsObjetivo is not null)
        {
            if (d.IdOsObjetivo <= 0) return ("La orden a resolver no es válida.", null);
            if (d.IdOsObjetivo != c.IdOsA && d.IdOsObjetivo != c.IdOsB) return ("La orden a resolver no forma parte de este conflicto.", null);
        }
        if (d.IdMotivo is not null && d.IdMotivo <= 0) return ("El motivo de reprogramación no es válido.", null);

        var comentario = (d.Comentario ?? string.Empty).Trim();
        if (comentario.Length > MaxComentario) return ($"El comentario no puede superar los {MaxComentario} caracteres.", null);
        if (comentario.Any(ch => char.IsControl(ch) && ch is not ('\n' or '\r' or '\t'))) return ("El comentario tiene caracteres no válidos.", null);

        DateOnly? fecha = null;
        TimeOnly? inicio = null, fin = null;
        long? nuevo = null;
        if (opcion == "reasignar")
        {
            if (d.IdNuevoTecnico is not > 0) return ("Selecciona el técnico que asumirá el servicio.", null);
            if (d.IdNuevoTecnico == c.IdTecnico) return ("El nuevo técnico debe ser distinto del técnico en conflicto.", null);
            nuevo = d.IdNuevoTecnico;
        }
        else
        {
            if (!DateOnly.TryParseExact((d.Fecha ?? string.Empty).Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var f)) return ("Indica la nueva fecha del servicio.", null);
            if (f < hoyLima) return ("La nueva fecha no puede ser anterior a hoy.", null);
            if (!TimeOnly.TryParseExact((d.HoraInicio ?? string.Empty).Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var hi)) return ("La hora de inicio no es válida: usa HH:mm.", null);
            if (!TimeOnly.TryParseExact((d.HoraFin ?? string.Empty).Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var hf)) return ("La hora de fin no es válida: usa HH:mm.", null);
            if (hf <= hi) return ("La hora de fin debe ser posterior a la de inicio.", null);
            fecha = f; inicio = hi; fin = hf;
        }

        return (null, new ResolucionConflictoDatos(c.Tipo, c.IdTecnico, c.IdOsA, c.IdOsB, opcion, d.IdOsObjetivo, nuevo, fecha, inicio, fin, d.IdMotivo, comentario.Length == 0 ? null : comentario));
    }
}

/// <summary>Agenda de la semana: matriz técnico × día con los servicios, la carga y los conflictos, con el alcance Área + Rol del jefe.</summary>
public class ObtenerAgendaAreaMovilCasoDeUso(IAgendaAreaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<AgendaAreaDto>> EjecutarAsync(long idUsuario, string? desde, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<AgendaAreaDto>(1, "No se pudo identificar al usuario."));
        var hoyLima = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-5));
        var v = ValidacionAgendaAreaMovil.NormalizarDesde(desde, hoyLima);
        return v.Error is not null
            ? Task.FromResult(new RespuestaDto<AgendaAreaDto>(1, v.Error))
            : repositorio.ObtenerAsync(idUsuario, v.Desde, ct);
    }
}

/// <summary>Detalle de un conflicto: sus servicios, el técnico sugerido y los motivos de reprogramación.</summary>
public class ObtenerConflictoAgendaMovilCasoDeUso(IAgendaAreaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<AgendaConflictoDetalleDto>> EjecutarAsync(long idUsuario, string? tipo, long? idTecnico, long? idOsA, long? idOsB, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<AgendaConflictoDetalleDto>(1, "No se pudo identificar al usuario."));
        var v = ValidacionAgendaAreaMovil.NormalizarConflicto(tipo, idTecnico, idOsA, idOsB);
        return v.Error is not null
            ? Task.FromResult(new RespuestaDto<AgendaConflictoDetalleDto>(1, v.Error))
            : repositorio.ObtenerConflictoAsync(idUsuario, v.Tipo, v.IdTecnico, v.IdOsA, v.IdOsB, ct);
    }
}

/// <summary>Resolver un conflicto: cambiar de técnico, cambiar el horario o reprogramar con motivo. Directa o solicitud según el permiso (lo decide el SP de la intranet).</summary>
public class ResolverConflictoAgendaMovilCasoDeUso(IAgendaAreaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ResolucionConflictoAgendaDto>> EjecutarAsync(long idUsuario, ResolverConflictoAgendaDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<ResolucionConflictoAgendaDto>(1, "No se pudo identificar al usuario."));
        var hoyLima = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-5));
        var v = ValidacionAgendaAreaMovil.NormalizarResolucion(dto, hoyLima);
        return v.Error is not null || v.Datos is null
            ? Task.FromResult(new RespuestaDto<ResolucionConflictoAgendaDto>(1, v.Error ?? "Indica cómo resolver el conflicto."))
            : repositorio.ResolverAsync(idUsuario, v.Datos, ct);
    }
}
