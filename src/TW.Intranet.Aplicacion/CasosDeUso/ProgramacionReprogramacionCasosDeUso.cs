using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-38 Reprogramación y Cancelación de la Programación (Sprint 5) ─────────────────────────────────────

/// <summary>
/// Validación de la entrada de la HU-38. Desarrollo seguro: identificadores positivos, motivo del catálogo (lo valida el SP),
/// listas con tope, fechas y horas con formato estricto, decisión de lista cerrada y textos con largo máximo y sin caracteres de
/// control. Nada inválido llega al SP. El circuito (directa o solicitud) NO lo elige el cliente: lo decide el SP con el permiso.
/// </summary>
internal static class EntradaReprogramacion
{
    internal const int MaxComentarioReprogramar = 400;
    internal const int MaxComentarioCancelar    = 500;
    internal const int MaxComentarioResolver    = 500;
    internal const int MaxApoyo                 = 9;

    private static readonly string[] Decisiones = ["aprobar", "rechazar"];

    internal static string? ErrorTexto(string? t, int max, string campo)
    {
        if (t is { Length: > 0 } && t.Length > max)
            return $"{campo} no puede superar {max} caracteres.";
        if (t is not null && t.Any(c => char.IsControl(c) && c is not ('\n' or '\r' or '\t')))
            return $"{campo} contiene caracteres no válidos.";
        return null;
    }

    internal static (NuevaReprogramacion? Reprogramacion, string? Error) NormalizarReprogramar(long idProgramacion, ReprogramarProgramacionDto? d)
    {
        if (idProgramacion <= 0)
            return (null, "Indica la programación.");
        if (d is null)
            return (null, "Indica los cambios y el motivo de la reprogramación.");
        if (d.IdMotivo <= 0)
            return (null, "Selecciona el motivo de la reprogramación.");

        var comentario = d.Comentario?.Trim();
        var errorTexto = ErrorTexto(comentario, MaxComentarioReprogramar, "El comentario");
        if (errorTexto is not null)
            return (null, errorTexto);

        DateTime? fecha = null;
        if (d.Fecha is not null)
        {
            if (!EntradaProgramar.FechaEnRango(d.Fecha.Value))
                return (null, "La fecha de ejecución no es válida.");
            if (d.Fecha.Value.Date < DateTime.Today)
                return (null, "La fecha de ejecución no puede ser anterior a hoy.");
            fecha = d.Fecha.Value.Date;
        }

        TimeSpan? inicio = null, fin = null;
        if (!string.IsNullOrWhiteSpace(d.HoraInicio))
        {
            if (!EntradaProgramar.TryHora(d.HoraInicio, out var h)) return (null, "La hora de inicio debe tener el formato HH:mm.");
            inicio = h;
        }
        if (!string.IsNullOrWhiteSpace(d.HoraFin))
        {
            if (!EntradaProgramar.TryHora(d.HoraFin, out var h)) return (null, "La hora fin debe tener el formato HH:mm.");
            fin = h;
        }
        if (inicio is not null && fin is not null && fin <= inicio)
            return (null, "La hora fin estimada debe ser posterior a la hora de inicio.");

        if (d.IdTecnicoPrincipal is <= 0)
            return (null, "El técnico principal no es válido.");

        IReadOnlyList<long>? apoyo = null;
        if (d.IdsTecnicosApoyo is not null)
        {
            var lista = d.IdsTecnicosApoyo.Distinct().ToList();
            if (lista.Any(id => id <= 0)) return (null, "Los técnicos de apoyo no son válidos.");
            if (d.IdTecnicoPrincipal is not null) lista.Remove(d.IdTecnicoPrincipal.Value);
            if (lista.Count > MaxApoyo) return (null, $"Una programación admite hasta {MaxApoyo} técnicos de apoyo.");
            apoyo = lista;
        }

        IReadOnlyList<long>? equipos = null;
        if (d.IdsEquipos is not null)
        {
            var lista = d.IdsEquipos.Distinct().ToList();
            if (lista.Any(id => id <= 0)) return (null, "Los equipos seleccionados no son válidos.");
            if (lista.Count > EntradaProgramar.MaxEquipos) return (null, $"Una programación admite hasta {EntradaProgramar.MaxEquipos} equipos.");
            equipos = lista;
        }

        return (new NuevaReprogramacion(idProgramacion, fecha, inicio, fin, d.IdTecnicoPrincipal, apoyo, equipos,
            d.IdMotivo, string.IsNullOrEmpty(comentario) ? null : comentario), null);
    }

    internal static (ResolucionSolicitudNormalizada? Resolucion, string? Error) NormalizarResolucion(long idSolicitud, string decision, ResolverSolicitudDto? d)
    {
        if (idSolicitud <= 0)
            return (null, "Indica la solicitud.");
        var dec = decision.Trim().ToLowerInvariant();
        if (!Decisiones.Contains(dec))
            return (null, "La decisión no es válida: usa aprobar o rechazar.");

        var comentario = d?.Comentario?.Trim();
        var errorTexto = ErrorTexto(comentario, MaxComentarioResolver, "El comentario");
        if (errorTexto is not null)
            return (null, errorTexto);
        if (dec == "rechazar" && string.IsNullOrEmpty(comentario))
            return (null, "Indica el motivo del rechazo.");

        return (new ResolucionSolicitudNormalizada(idSolicitud, dec, string.IsNullOrEmpty(comentario) ? null : comentario), null);
    }

    internal static (NuevaCancelacion? Cancelacion, string? Error) NormalizarCancelacion(long idProgramacion, CancelarProgramacionDto? d)
    {
        if (idProgramacion <= 0)
            return (null, "Indica la programación.");
        if (d is null || d.IdMotivo <= 0)
            return (null, "Selecciona el motivo de la cancelación.");

        var comentario = d.Comentario?.Trim();
        var errorTexto = ErrorTexto(comentario, MaxComentarioCancelar, "La justificación");
        if (errorTexto is not null)
            return (null, errorTexto);

        return (new NuevaCancelacion(idProgramacion, d.IdMotivo, string.IsNullOrEmpty(comentario) ? null : comentario), null);
    }
}

/// <summary>Datos de la ficha "Reprogramar Servicio": programación, técnicos y equipos disponibles, motivos y circuito del usuario.</summary>
public class PrepararReprogramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<ProgramacionPreparadaDto>> EjecutarAsync(long idProgramacion, long idUsuario, CancellationToken ct = default)
        => idProgramacion <= 0
            ? Task.FromResult(new RespuestaDto<ProgramacionPreparadaDto>(1, "Indica la programación."))
            : repositorio.PrepararReprogramacionAsync(idProgramacion, idUsuario, ct);
}

/// <summary>
/// Reprograma la programación activa. Jefe de Operaciones: edición directa firmada en el historial. Asistente: crea una solicitud
/// pendiente. Si cambia fecha u hora vuelve a PENDIENTE CONFIRMACIÓN CLIENTE.
/// </summary>
public class ReprogramarProgramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<ReprogramacionResultadoDto>> EjecutarAsync(
        long idProgramacion, ReprogramarProgramacionDto? d, long idUsuario, CancellationToken ct = default)
    {
        var (n, error) = EntradaReprogramacion.NormalizarReprogramar(idProgramacion, d);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ReprogramacionResultadoDto>(1, error))
            : repositorio.ReprogramarAsync(n!, idUsuario, ct);
    }
}

public class ObtenerSolicitudReprogramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<SolicitudReprogramacionDto>> EjecutarAsync(long idSolicitud, long idUsuario, CancellationToken ct = default)
        => idSolicitud <= 0
            ? Task.FromResult(new RespuestaDto<SolicitudReprogramacionDto>(1, "Indica la solicitud."))
            : repositorio.ObtenerSolicitudAsync(idSolicitud, idUsuario, ct);
}

/// <summary>Aprobar (aplica los cambios) o rechazar (motivo obligatorio, la programación queda igual). Solo el Jefe.</summary>
public class ResolverSolicitudReprogramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<SolicitudResueltaDto>> EjecutarAsync(
        long idSolicitud, string decision, ResolverSolicitudDto? d, long idUsuario, CancellationToken ct = default)
    {
        var (n, error) = EntradaReprogramacion.NormalizarResolucion(idSolicitud, decision, d);
        return error is not null
            ? Task.FromResult(new RespuestaDto<SolicitudResueltaDto>(1, error))
            : repositorio.ResolverSolicitudAsync(n!, idUsuario, ct);
    }
}

/// <summary>El solicitante retira su solicitud pendiente.</summary>
public class RetirarSolicitudReprogramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<SolicitudResueltaDto>> EjecutarAsync(long idSolicitud, long idUsuario, CancellationToken ct = default)
        => idSolicitud <= 0
            ? Task.FromResult(new RespuestaDto<SolicitudResueltaDto>(1, "Indica la solicitud."))
            : repositorio.RetirarSolicitudAsync(idSolicitud, idUsuario, ct);
}

public class PrepararCancelacionProgramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<CancelacionPreparadaDto>> EjecutarAsync(long idProgramacion, long idUsuario, CancellationToken ct = default)
        => idProgramacion <= 0
            ? Task.FromResult(new RespuestaDto<CancelacionPreparadaDto>(1, "Indica la programación."))
            : repositorio.PrepararCancelacionAsync(idProgramacion, idUsuario, ct);
}

/// <summary>Cancela la programación (terminal, sin aprobación, cualquier rol con prog_gestionar). La OS sigue emitida y vuelve a Pendientes.</summary>
public class CancelarProgramacionCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<CancelacionResultadoDto>> EjecutarAsync(
        long idProgramacion, CancelarProgramacionDto? d, long idUsuario, CancellationToken ct = default)
    {
        var (n, error) = EntradaReprogramacion.NormalizarCancelacion(idProgramacion, d);
        return error is not null
            ? Task.FromResult(new RespuestaDto<CancelacionResultadoDto>(1, error))
            : repositorio.CancelarAsync(n!, idUsuario, ct);
    }
}

/// <summary>Historial completo de programaciones de una OS (activas y canceladas) con su timeline.</summary>
public class ObtenerHistorialProgramacionesOsCasoDeUso(IProgramacionReprogramacionRepositorio repositorio)
{
    public Task<RespuestaDto<HistorialProgramacionesOsDto>> EjecutarAsync(long idOs, long idUsuario, CancellationToken ct = default)
        => idOs <= 0
            ? Task.FromResult(new RespuestaDto<HistorialProgramacionesOsDto>(1, "Indica la orden de servicio."))
            : repositorio.ObtenerHistorialOsAsync(idOs, idUsuario, ct);
}
