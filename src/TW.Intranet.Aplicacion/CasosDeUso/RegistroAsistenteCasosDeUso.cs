using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-53 Registro operativo del Asistente de Seguimiento (Sprint 5) ───────────────────────────────────

/// <summary>
/// Validación de entrada. Desarrollo seguro: listas cerradas (modo, fuente, impacto, estado), longitudes máximas, sin caracteres de control,
/// identificadores positivos, evidencia solo https o ruta del sistema (nunca javascript:/data:), vínculo con alfabeto estricto. El SP vuelve a
/// validar todo (defensa en profundidad) y los valores viajan siempre como parámetros (nunca se concatena SQL).
/// </summary>
internal static partial class EntradaRegistroAsistente
{
    internal static readonly string[] Modos    = ["observacion", "demora", "cambio_estado"];
    internal static readonly string[] Fuentes  = ["llamada_telefonica", "whatsapp", "contacto_planta", "observacion_directa"];
    internal static readonly string[] Impactos = ["retrasa", "detiene"];
    internal static readonly string[] Estados  = ["salida", "en_ruta", "llegada", "ingreso", "inicio", "finalizado"];

    [GeneratedRegex(@"^[edia][0-9]{1,18}$")]
    private static partial Regex ClaveVinculo();

    [GeneratedRegex(@"^(https://[^\s<>""\\]+|/[^/\s<>""\\][^\s<>""\\]*)$")]
    private static partial Regex Evidencia();

    private static bool TieneControl(string t) => t.Any(c => char.IsControl(c) && c != '\n' && c != '\r' && c != '\t');

    internal static string? ErrorIdOs(long idOs) => idOs <= 0 ? "El servicio indicado no es válido." : null;

    private static string? Texto(string? v, string nombre, int min, int max, out string limpio)
    {
        limpio = (v ?? "").Trim();
        if (limpio.Length == 0 && min > 0) return $"{nombre} es obligatorio.";
        if (limpio.Length > 0 && limpio.Length < min) return $"{nombre} debe tener al menos {min} caracteres.";
        if (limpio.Length > max) return $"{nombre} no puede superar los {max} caracteres.";
        if (TieneControl(limpio)) return $"{nombre} contiene caracteres no permitidos.";
        return null;
    }

    internal static (RegistroAsistenteNormalizado? Datos, string? Error) Normalizar(RegistrarAsistenteSolicitudDto? s)
    {
        if (s is null) return (null, "La solicitud no es válida.");
        var modo = (s.Modo ?? "").Trim().ToLowerInvariant();
        if (!Modos.Contains(modo)) return (null, "El modo de registro no es válido.");

        switch (modo)
        {
            case "observacion":
            {
                if (Texto(s.Descripcion, "La descripción", 1, 500, out var d) is { } e) return (null, e);
                var f = (s.Fuente ?? "").Trim().ToLowerInvariant();
                if (f.Length > 0 && !Fuentes.Contains(f)) return (null, "La fuente de la información no es válida.");
                var v = (s.Vinculo ?? "").Trim().ToLowerInvariant();
                if (v.Length > 0 && !ClaveVinculo().IsMatch(v)) return (null, "El evento a vincular no es válido.");
                return (new RegistroAsistenteNormalizado(modo, d, f.Length == 0 ? null : f, v.Length == 0 ? null : v, null, null, null, null, null, null, null), null);
            }
            case "demora":
            {
                if (s.IdTipo is not > 0) return (null, "El tipo de demora o incidente no es válido.");
                if (Texto(s.Descripcion, "La descripción", 1, 500, out var d) is { } e) return (null, e);
                if (s.DuracionMin is { } m && (m < 1 || m > 1440)) return (null, "La duración estimada debe estar entre 1 y 1440 minutos.");
                var imp = string.IsNullOrWhiteSpace(s.Impacto) ? "retrasa" : s.Impacto.Trim().ToLowerInvariant();
                if (!Impactos.Contains(imp)) return (null, "El impacto en la ruta no es válido.");
                var ev = (s.EvidenciaUrl ?? "").Trim();
                if (ev.Length > 0 && (ev.Length > 500 || !Evidencia().IsMatch(ev) || ev.Contains("..")))
                    return (null, "La evidencia fotográfica debe ser un enlace https o una ruta del sistema.");
                return (new RegistroAsistenteNormalizado(modo, d, null, null, s.IdTipo, s.DuracionMin, imp, ev.Length == 0 ? null : ev, null, null, null), null);
            }
            default:
            {
                var est = (s.NuevoEstado ?? "").Trim().ToLowerInvariant();
                if (!Estados.Contains(est)) return (null, "El nuevo estado no es válido.");
                if (s.IdMotivo is not > 0) return (null, "El motivo del cambio manual no es válido.");
                if (Texto(s.Comentario, "El comentario de justificación", 10, 1000, out var c) is { } e) return (null, e);
                return (new RegistroAsistenteNormalizado(modo, null, null, null, null, null, null, null, est, s.IdMotivo, c), null);
            }
        }
    }
}

public class ObtenerFormularioRegistroAsistenteCasoDeUso(IRegistroAsistenteRepositorio repositorio)
{
    public Task<RespuestaDto<FormularioRegistroAsistenteDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaRegistroAsistente.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<FormularioRegistroAsistenteDto>(1, e)) : repositorio.ObtenerFormularioAsync(idUsuario, idOs, ct);
}

public class RegistrarAsistenteServicioRutaCasoDeUso(IRegistroAsistenteRepositorio repositorio)
{
    public Task<RespuestaDto<RegistroAsistenteCreadoDto>> EjecutarAsync(long idUsuario, long idOs, RegistrarAsistenteSolicitudDto? solicitud, CancellationToken ct = default)
    {
        if (EntradaRegistroAsistente.ErrorIdOs(idOs) is { } e)
            return Task.FromResult(new RespuestaDto<RegistroAsistenteCreadoDto>(1, e));
        var (datos, error) = EntradaRegistroAsistente.Normalizar(solicitud);
        return error is not null || datos is null
            ? Task.FromResult(new RespuestaDto<RegistroAsistenteCreadoDto>(1, error ?? "La solicitud no es válida."))
            : repositorio.RegistrarAsync(idUsuario, idOs, datos, ct);
    }
}
