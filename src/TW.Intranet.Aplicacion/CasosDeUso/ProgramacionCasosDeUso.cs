using System.Globalization;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-36 Programación de OS y asignación de recursos (Sprint 5) ─────────────

/// <summary>
/// Validación de la entrada de la programación. Desarrollo seguro: horas con formato estricto, fechas en un rango razonable,
/// identificadores positivos y sin repetir, listas con tope y textos con largo máximo. Lo que llega al SP ya está depurado.
/// </summary>
internal static partial class EntradaProgramar
{
    internal const int MaxApoyo         = 9;
    internal const int MaxEquipos       = 200;
    internal const int MaxObservaciones = 500;
    internal const int MaxBusqueda      = 100;
    internal const int MaxTecnicosDerivar = 10;
    internal const int MaxComentario    = 500;

    /// <summary>Pestañas del modal "Asignar Recurso".</summary>
    private static readonly string[] TiposRecurso = ["tecnico", "metrologo", "externo"];

    [GeneratedRegex("^[a-z0-9_]{1,60}$")]
    private static partial Regex CodigoSede();

    private static readonly string[] FormatosHora = [@"h\:mm", @"hh\:mm", @"hh\:mm\:ss"];

    /// <summary>HH:mm (o HH:mm:ss), de 00:00 a 23:59.</summary>
    internal static bool TryHora(string? texto, out TimeSpan hora)
    {
        hora = default;
        return !string.IsNullOrWhiteSpace(texto)
            && TimeSpan.TryParseExact(texto.Trim(), FormatosHora, CultureInfo.InvariantCulture, out hora)
            && hora >= TimeSpan.Zero && hora < TimeSpan.FromHours(24);
    }

    /// <summary>Fecha de un servicio: de hace un año a dos años adelante (el SP exige además que no sea anterior a hoy al crear).</summary>
    internal static bool FechaEnRango(DateTime fecha)
        => fecha.Date >= DateTime.Today.AddYears(-1) && fecha.Date <= DateTime.Today.AddYears(2);

    internal static (FiltroTecnicosProgramacion? Filtro, string? Error) NormalizarFiltro(FiltrosTecnicosProgramacionDto f)
    {
        var tieneInicio = !string.IsNullOrWhiteSpace(f.HoraInicio);
        var tieneFin    = !string.IsNullOrWhiteSpace(f.HoraFin);

        TimeSpan? inicio = null, fin = null;
        if (tieneInicio || tieneFin)
        {
            if (!tieneInicio || !tieneFin)
                return (null, "Indica la hora de inicio y la hora fin, o ninguna de las dos.");
            if (!TryHora(f.HoraInicio, out var i) || !TryHora(f.HoraFin, out var h))
                return (null, "Las horas deben tener el formato HH:mm.");
            if (h <= i)
                return (null, "La hora fin debe ser posterior a la hora de inicio.");
            if (f.Fecha is null)
                return (null, "Indica la fecha para consultar la disponibilidad.");
            inicio = i; fin = h;
        }

        if (f.Fecha is { } fecha && !FechaEnRango(fecha))
            return (null, "La fecha no es válida.");

        var busqueda = f.Busqueda?.Trim();
        if (busqueda is { Length: > MaxBusqueda })
            busqueda = busqueda[..MaxBusqueda];

        var sede = f.SedeOperativa?.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(sede) && !CodigoSede().IsMatch(sede))
            return (null, "La sede operativa no es válida.");

        var tipo = f.TipoRecurso?.Trim().ToLowerInvariant();
        if (tipo is "todos") tipo = null;
        if (!string.IsNullOrEmpty(tipo) && !TiposRecurso.Contains(tipo))
            return (null, "El tipo de recurso no es válido: usa tecnico, metrologo o externo.");

        return (new FiltroTecnicosProgramacion(
            f.Fecha?.Date, inicio, fin,
            f.SoloDisponibles, f.SoloSsomaConforme,
            string.IsNullOrEmpty(busqueda) ? null : busqueda,
            string.IsNullOrEmpty(sede) ? null : sede,
            string.IsNullOrEmpty(tipo) ? null : tipo), null);
    }

    /// <summary>Derivación a SSOMA: orden válida, de 1 a 10 técnicos sin repetir, fecha razonable y nota con tope.</summary>
    internal static (NuevaDerivacionSsoma? Derivacion, string? Error) NormalizarDerivacion(long idOs, DerivarSsomaDto? d)
    {
        if (idOs <= 0)
            return (null, "Indica la orden de servicio.");
        if (d is null)
            return (null, "Indica los técnicos a revisar.");

        var tecnicos = (d.IdsTecnicos ?? []).Distinct().ToList();
        if (tecnicos.Count == 0)
            return (null, "Indica al menos un técnico a revisar.");
        if (tecnicos.Any(id => id <= 0))
            return (null, "Los técnicos indicados no son válidos.");
        if (tecnicos.Count > MaxTecnicosDerivar)
            return (null, $"Puedes derivar hasta {MaxTecnicosDerivar} técnicos a la vez.");

        if (d.Fecha is { } fecha && !FechaEnRango(fecha))
            return (null, "La fecha no es válida.");

        var comentario = d.Comentario?.Trim();
        if (comentario is { Length: > MaxComentario })
            return (null, $"La nota para SSOMA no puede superar {MaxComentario} caracteres.");

        return (new NuevaDerivacionSsoma(idOs, d.Fecha?.Date, tecnicos, string.IsNullOrEmpty(comentario) ? null : comentario), null);
    }

    internal static (NuevaProgramacion? Programacion, string? Error) Normalizar(CrearProgramacionDto d)
    {
        if (d.IdOs <= 0)
            return (null, "Indica la orden de servicio a programar.");

        if (d.FechaEjecucion is null)
            return (null, "Indica la fecha de ejecución.");
        if (!FechaEnRango(d.FechaEjecucion.Value))
            return (null, "La fecha de ejecución no es válida.");
        if (d.FechaEjecucion.Value.Date < DateTime.Today)
            return (null, "La fecha de ejecución no puede ser anterior a hoy.");

        if (!TryHora(d.HoraInicio, out var inicio) || !TryHora(d.HoraFin, out var fin))
            return (null, "Las horas de inicio y fin deben tener el formato HH:mm.");
        if (fin <= inicio)
            return (null, "La hora fin estimada debe ser posterior a la hora de inicio.");

        if (d.IdTecnicoPrincipal <= 0)
            return (null, "Selecciona al menos un técnico: el técnico principal es obligatorio.");

        var apoyo = (d.IdsTecnicosApoyo ?? []).Distinct().ToList();
        if (apoyo.Any(id => id <= 0))
            return (null, "Los técnicos de apoyo no son válidos.");
        apoyo.Remove(d.IdTecnicoPrincipal);
        if (apoyo.Count > MaxApoyo)
            return (null, $"Una programación admite hasta {MaxApoyo} técnicos de apoyo.");

        var equipos = (d.IdsEquipos ?? []).Distinct().ToList();
        if (equipos.Any(id => id <= 0))
            return (null, "Los equipos seleccionados no son válidos.");
        if (equipos.Count > MaxEquipos)
            return (null, $"Una programación admite hasta {MaxEquipos} equipos.");

        var obs = d.Observaciones?.Trim();
        if (obs is { Length: > MaxObservaciones })
            return (null, $"Las observaciones no pueden superar {MaxObservaciones} caracteres.");

        return (new NuevaProgramacion(d.IdOs, d.FechaEjecucion.Value.Date, inicio, fin, d.IdTecnicoPrincipal,
                                      apoyo, equipos, string.IsNullOrEmpty(obs) ? null : obs), null);
    }
}

/// <summary>HU-36 Ficha "Programar Servicio": datos heredados de la OS, equipos y requisitos SSOMA.</summary>
public class PrepararProgramacionCasoDeUso(IProgramacionRepositorio repositorio)
{
    public Task<RespuestaDto<FichaProgramacionDto>> EjecutarAsync(long idOs, long idUsuario, CancellationToken ct = default)
        => idOs <= 0
            ? Task.FromResult(new RespuestaDto<FichaProgramacionDto>(1, "Indica la orden de servicio a programar."))
            : repositorio.ObtenerFichaAsync(idOs, idUsuario, ct);
}

/// <summary>HU-36 Buscador de técnicos con disponibilidad, carga del día, SSOMA y scorecard.</summary>
public class BuscarTecnicosProgramacionCasoDeUso(IProgramacionRepositorio repositorio)
{
    public Task<RespuestaDto<BusquedaTecnicosDto>> EjecutarAsync(
        long idOs, FiltrosTecnicosProgramacionDto f, long idUsuario, CancellationToken ct = default)
    {
        if (idOs <= 0)
            return Task.FromResult(new RespuestaDto<BusquedaTecnicosDto>(1, "Indica la orden de servicio a programar."));

        var (filtro, error) = EntradaProgramar.NormalizarFiltro(f);
        return error is not null
            ? Task.FromResult(new RespuestaDto<BusquedaTecnicosDto>(1, error))
            : repositorio.BuscarTecnicosAsync(idOs, filtro!, idUsuario, ct);
    }
}

/// <summary>
/// HU-36 Crea la programación de una OS emitida: cronograma, técnicos y equipos. Las reglas de negocio (OS emitida, sin
/// otra programación activa, técnicos programables, sin solapamiento, SSOMA) las valida el SP en una transacción.
/// </summary>
public class CrearProgramacionCasoDeUso(IProgramacionRepositorio repositorio)
{
    public Task<RespuestaDto<ProgramacionCreadaDto>> EjecutarAsync(CrearProgramacionDto d, long idUsuario, CancellationToken ct = default)
    {
        var (programacion, error) = EntradaProgramar.Normalizar(d);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ProgramacionCreadaDto>(1, error))
            : repositorio.CrearAsync(programacion!, idUsuario, ct);
    }
}

/// <summary>
/// HU-36 "Derivar al área SSOMA": avisa a SSOMA qué técnicos no cumplen los requisitos del cliente/zona de la orden y qué les
/// falta. La evaluación y el control de avisos repetidos los hace el SP.
/// </summary>
public class DerivarSsomaProgramacionCasoDeUso(IProgramacionRepositorio repositorio)
{
    public Task<RespuestaDto<DerivacionSsomaDto>> EjecutarAsync(long idOs, DerivarSsomaDto? d, long idUsuario, CancellationToken ct = default)
    {
        var (derivacion, error) = EntradaProgramar.NormalizarDerivacion(idOs, d);
        return error is not null
            ? Task.FromResult(new RespuestaDto<DerivacionSsomaDto>(1, error))
            : repositorio.DerivarSsomaAsync(derivacion!, idUsuario, ct);
    }
}
