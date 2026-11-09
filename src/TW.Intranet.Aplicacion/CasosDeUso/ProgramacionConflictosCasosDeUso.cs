using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-39 Carga de Recursos y Alertas de Conflicto Sobrevenido (Sprint 5) ─────────────────────────────────

/// <summary>
/// Validación de la entrada de la HU-39. Desarrollo seguro: tipo y opción de listas cerradas, identificadores positivos, fechas y
/// horas con formato estricto, comentario con largo máximo y sin caracteres de control. Nada inválido llega al SP. El circuito
/// (directa o solicitud) NO lo elige el cliente: lo decide el SP con el permiso del usuario del token.
/// </summary>
internal static class EntradaConflictos
{
    internal const int MaxComentario = 300;

    internal static readonly string[] Tipos    = ["baja", "ssoma_vencido", "solapamiento", "extension_duracion"];
    internal static readonly string[] Opciones = ["reasignar", "reprogramar"];

    private static bool EsCruce(string tipo) => tipo is "solapamiento" or "extension_duracion";

    /// <summary>Valida el conflicto que se quiere abrir (modal). Devuelve el tipo normalizado.</summary>
    internal static (string? Tipo, string? Error) NormalizarConflicto(string? tipo, long idTecnico, long idOsA, long? idOsB)
    {
        var t = tipo?.Trim().ToLowerInvariant() ?? "";
        if (!Tipos.Contains(t))
            return (null, "El tipo de conflicto no es válido.");
        if (idTecnico <= 0 || idOsA <= 0)
            return (null, "Indica el técnico y la orden del conflicto.");
        if (EsCruce(t) && (idOsB is null or <= 0 || idOsB == idOsA))
            return (null, "Indica las dos órdenes que se cruzan.");
        if (!EsCruce(t) && idOsB is <= 0)
            return (null, "La segunda orden no es válida.");
        return (t, null);
    }

    internal static (ResolucionConflictoNormalizada? Resolucion, string? Error) NormalizarResolucion(ResolverConflictoDto? d)
    {
        if (d is null)
            return (null, "Indica cómo resolver el conflicto.");
        var (tipo, error) = NormalizarConflicto(d.Tipo, d.IdTecnico, d.IdOsA, d.IdOsB);
        if (error is not null)
            return (null, error);

        var opcion = d.Opcion?.Trim().ToLowerInvariant() ?? "";
        if (!Opciones.Contains(opcion))
            return (null, "Selecciona cómo resolver el conflicto: reasignar o reprogramar.");

        var objetivo = d.IdOsObjetivo ?? d.IdOsA;
        if (objetivo <= 0 || (objetivo != d.IdOsA && objetivo != d.IdOsB))
            return (null, "La orden a resolver no forma parte de este conflicto.");

        var comentario = d.Comentario?.Trim();
        var errorTexto = EntradaReprogramacion.ErrorTexto(comentario, MaxComentario, "El comentario");
        if (errorTexto is not null)
            return (null, errorTexto);

        long? nuevo = null;
        DateTime? fecha = null;
        TimeSpan? inicio = null, fin = null;
        if (opcion == "reasignar")
        {
            if (d.IdNuevoTecnico is null or <= 0)
                return (null, "Selecciona el técnico que asumirá el servicio.");
            if (d.IdNuevoTecnico == d.IdTecnico)
                return (null, "El nuevo técnico debe ser distinto del técnico en conflicto.");
            nuevo = d.IdNuevoTecnico;
        }
        else
        {
            if (d.Fecha is null || string.IsNullOrWhiteSpace(d.HoraInicio) || string.IsNullOrWhiteSpace(d.HoraFin))
                return (null, "Indica la nueva fecha y el horario del servicio.");
            if (!EntradaProgramar.FechaEnRango(d.Fecha.Value))
                return (null, "La fecha de ejecución no es válida.");
            if (d.Fecha.Value.Date < DateTime.Today)
                return (null, "La fecha de ejecución no puede ser anterior a hoy.");
            if (!EntradaProgramar.TryHora(d.HoraInicio, out var hi)) return (null, "La hora de inicio debe tener el formato HH:mm.");
            if (!EntradaProgramar.TryHora(d.HoraFin, out var hf))    return (null, "La hora fin debe tener el formato HH:mm.");
            if (hf <= hi)
                return (null, "La hora fin estimada debe ser posterior a la hora de inicio.");
            fecha = d.Fecha.Value.Date; inicio = hi; fin = hf;
        }

        return (new ResolucionConflictoNormalizada(tipo!, d.IdTecnico, d.IdOsA, d.IdOsB, opcion, objetivo, nuevo, fecha, inicio, fin,
            string.IsNullOrEmpty(comentario) ? null : comentario), null);
    }

    internal static (DateTime? Fecha, string? Error) NormalizarDia(long idTecnico, DateTime? fecha)
    {
        if (idTecnico <= 0)
            return (null, "Indica el técnico.");
        if (fecha is null)
            return (null, "Indica el día de la celda.");
        if (!EntradaProgramar.FechaEnRango(fecha.Value))
            return (null, "El día no es válido.");
        return (fecha.Value.Date, null);
    }
}

/// <summary>Lista de alertas de conflicto sobrevenido (arriba de la matriz de carga).</summary>
public class ObtenerConflictosProgramacionCasoDeUso(IProgramacionConflictosRepositorio repositorio)
{
    public Task<RespuestaDto<ConflictosProgramacionDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => repositorio.ObtenerConflictosAsync(idUsuario, ct);
}

/// <summary>Modal "Resolver Conflicto de Programación": servicios, impacto, opciones y recursos sugeridos.</summary>
public class ObtenerConflictoProgramacionCasoDeUso(IProgramacionConflictosRepositorio repositorio)
{
    public Task<RespuestaDto<ConflictoModalDto>> EjecutarAsync(
        string? tipo, long idTecnico, long idOsA, long? idOsB, long idUsuario, CancellationToken ct = default)
    {
        var (t, error) = EntradaConflictos.NormalizarConflicto(tipo, idTecnico, idOsA, idOsB);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ConflictoModalDto>(1, error))
            : repositorio.ObtenerConflictoAsync(t!, idTecnico, idOsA, idOsB, idUsuario, ct);
    }
}

/// <summary>
/// Aplica la resolución elegida. Reutiliza el circuito de la HU-38: Jefe = edición directa; Asistente = Solicitud de Reprogramación.
/// El motivo se autocompleta con el del conflicto detectado.
/// </summary>
public class ResolverConflictoProgramacionCasoDeUso(IProgramacionConflictosRepositorio repositorio)
{
    public Task<RespuestaDto<ReprogramacionResultadoDto>> EjecutarAsync(ResolverConflictoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (n, error) = EntradaConflictos.NormalizarResolucion(dto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ReprogramacionResultadoDto>(1, error))
            : repositorio.ResolverConflictoAsync(n!, idUsuario, ct);
    }
}

/// <summary>Panel lateral de la matriz: programaciones de un técnico un día.</summary>
public class ObtenerProgramacionesTecnicoDiaCasoDeUso(IProgramacionConflictosRepositorio repositorio)
{
    public Task<RespuestaDto<TecnicoDiaDto>> EjecutarAsync(long idTecnico, DateTime? fecha, long idUsuario, CancellationToken ct = default)
    {
        var (f, error) = EntradaConflictos.NormalizarDia(idTecnico, fecha);
        return error is not null
            ? Task.FromResult(new RespuestaDto<TecnicoDiaDto>(1, error))
            : repositorio.ObtenerProgramacionesTecnicoDiaAsync(idTecnico, f!.Value, idUsuario, ct);
    }
}
