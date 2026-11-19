using System.Globalization;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-36 — Mi equipo: asistencia y ubicación (Jefe de Área) + horas contabilizadas ────────────────────────────

/// <summary>
/// Validación de entrada de «Horas contabilizadas». Desarrollo seguro: el mes viene como «AAAA-MM» (nada más), no puede ser futuro ni de hace más de 24 meses. El SP lo vuelve a validar
/// (misma regla, mismos mensajes); aquí se corta antes de llegar a la base de datos.
/// </summary>
public static partial class ValidacionEquipoJefaturaMovil
{
    public const string MensajeMesInvalido = "El mes no es válido: usa el formato AAAA-MM.";
    public const string MensajeMesFuturo   = "No hay horas de un mes futuro.";
    public const string MensajeMesAntiguo  = "Solo se guarda el historial de los últimos 24 meses.";
    public const int MesesHistorial = 24;

    [GeneratedRegex(@"^\d{4}-(0[1-9]|1[0-2])$", RegexOptions.CultureInvariant)]
    private static partial Regex PatronMes();

    /// <summary>Devuelve el error, o el mes normalizado («AAAA-MM»; null = el mes actual, que resuelve el SP en hora de Lima). hoyLima = la fecha de hoy en Lima (UTC-5).</summary>
    public static (string? Error, string? Mes) NormalizarMes(string? mes, DateOnly hoyLima)
    {
        var texto = (mes ?? string.Empty).Trim();
        if (texto.Length == 0) return (null, null);
        if (!PatronMes().IsMatch(texto)) return (MensajeMesInvalido, null);

        var primero = DateOnly.ParseExact(texto + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture);
        var actual  = new DateOnly(hoyLima.Year, hoyLima.Month, 1);
        if (primero > actual) return (MensajeMesFuturo, null);
        if (primero < actual.AddMonths(-(MesesHistorial - 1))) return (MensajeMesAntiguo, null);
        return (null, texto);
    }
}

/// <summary>Cálculo puro de los acumulados de las horas contabilizadas (se prueba sin base de datos).</summary>
public static class CalculoHorasEquipo
{
    /// <summary>
    /// Semanas (lunes a domingo) que tocan el mes. Desde/Hasta son las fechas de la semana COMPLETA; los minutos y los días trabajados cuentan solo los días que el SP devolvió (los del mes).
    /// Una semana sin horas también aparece (con 0): el calendario muestra todas las semanas del mes.
    /// </summary>
    public static List<HoraSemanaDto> ArmarSemanas(string mes, IReadOnlyList<HoraDiaDto> dias)
    {
        var primero = DateOnly.ParseExact(mes + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture);
        var ultimo  = primero.AddMonths(1).AddDays(-1);
        var lunes   = primero.AddDays(-(((int)primero.DayOfWeek + 6) % 7));

        var porDia = dias
            .Select(d => (Fecha: DateOnly.ParseExact(d.Fecha, "yyyy-MM-dd", CultureInfo.InvariantCulture), d.Minutos))
            .ToList();

        var semanas = new List<HoraSemanaDto>();
        for (var desde = lunes; desde <= ultimo; desde = desde.AddDays(7))
        {
            var hasta = desde.AddDays(6);
            var enSemana = porDia.Where(d => d.Fecha >= desde && d.Fecha <= hasta && d.Fecha >= primero && d.Fecha <= ultimo).ToList();
            semanas.Add(new HoraSemanaDto(desde.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), hasta.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                                          enSemana.Sum(d => d.Minutos), enSemana.Count(d => d.Minutos > 0)));
        }
        return semanas;
    }
}

/// <summary>«Mi equipo»: KPIs y la lista de técnicos de hoy según el Reloj marcador, con el servicio y la ubicación de cada uno. Alcance Área + Rol de la app.</summary>
public class ObtenerEquipoJefaturaMovilCasoDeUso(IEquipoJefaturaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<EquipoJefaturaDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<EquipoJefaturaDto>(1, "No se pudo identificar al usuario."))
            : repositorio.ObtenerAsync(idUsuario, ct);
}

/// <summary>Ficha de un técnico del equipo: cargo, área, teléfono, SSOMA, marcaciones del día y carga de la semana.</summary>
public class ObtenerFichaEquipoTecnicoMovilCasoDeUso(IEquipoJefaturaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<FichaEquipoTecnicoDto>> EjecutarAsync(long idUsuario, long idTecnico, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<FichaEquipoTecnicoDto>(1, "No se pudo identificar al usuario."))
        : idTecnico <= 0 ? Task.FromResult(new RespuestaDto<FichaEquipoTecnicoDto>(1, "El técnico indicado no es válido."))
        : repositorio.ObtenerFichaAsync(idUsuario, idTecnico, ct);
}

/// <summary>Horas contabilizadas de un técnico en un mes: calendario, acumulado por semana, total del mes e historial guardado. Las semanas se arman aquí a partir de los días.</summary>
public class ObtenerHorasTecnicoMovilCasoDeUso(IEquipoJefaturaMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<HorasTecnicoDto>> EjecutarAsync(long idUsuario, long idTecnico, string? mes, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return new RespuestaDto<HorasTecnicoDto>(1, "No se pudo identificar al usuario.");
        if (idTecnico <= 0) return new RespuestaDto<HorasTecnicoDto>(1, "El técnico indicado no es válido.");

        var hoyLima = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-5));
        var v = ValidacionEquipoJefaturaMovil.NormalizarMes(mes, hoyLima);
        if (v.Error is not null) return new RespuestaDto<HorasTecnicoDto>(1, v.Error);

        var r = await repositorio.ObtenerHorasAsync(idUsuario, idTecnico, v.Mes, ct);
        if (r.Datos is not { } d) return new RespuestaDto<HorasTecnicoDto>(r.IdTipoMensaje, r.Mensaje);

        return new RespuestaDto<HorasTecnicoDto>(r.IdTipoMensaje, r.Mensaje,
            new HorasTecnicoDto(d.Tecnico, d.Mes, d.Dias, CalculoHorasEquipo.ArmarSemanas(d.Mes, d.Dias), d.TotalMinutos, d.DiasTrabajados, d.Servicios, d.Cerrado, d.Historial));
    }
}
