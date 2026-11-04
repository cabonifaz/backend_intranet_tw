using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-45 Asignación de Viáticos y Rendición de Gastos Operativos (Sprint 5) ───────────────────────────────

/// <summary>
/// Validación de la entrada de la HU-45. Desarrollo seguro: identificadores positivos, montos decimales positivos con 2 decimales como
/// máximo y tope, hasta 60 líneas, nombre de concepto nuevo con alfabeto estricto (letras, números y signos comunes), acción de lista
/// cerrada, comentario con largo máximo y sin caracteres de control, huella de versión con alfabeto estricto. El JSON que llega al SP
/// lo arma el servidor con serializador (nunca se concatena texto del cliente). El SP vuelve a validar todo.
/// </summary>
internal static class EntradaViaticos
{
    internal const int     MaxLineas      = 60;
    internal const int     MaxComentario  = 400;
    internal const int     MaxVersion     = 80;
    internal const decimal MontoMaximo    = 1_000_000m;   // tope duro de la API; el SP aplica el parámetro VIATICOS_MONTO_MAXIMO
    internal static readonly string[] Acciones = ["aprobar", "observar", "rechazar"];

    internal static bool NombreConceptoValido(string nombre)
    {
        if (nombre.Length is < 2 or > 60)
            return false;
        foreach (var c in nombre)
            if (!(char.IsLetterOrDigit(c) || c is ' ' or '/' or '.' or '-' or ',' or '(' or ')' or '&' or '+' or '#'))
                return false;
        return nombre.Any(char.IsLetterOrDigit);
    }

    internal static string? ErrorVersion(string? v)
    {
        if (string.IsNullOrWhiteSpace(v))
            return "Falta la versión de la asignación: vuelve a abrir la gestión de viáticos.";
        var t = v.Trim();
        if (t.Length > MaxVersion || !t.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '.' or '_'))
            return "La versión de la asignación no es válida: vuelve a abrir la gestión de viáticos.";
        return null;
    }

    internal static (GuardarViaticosNormalizado? Datos, string? Error) NormalizarGuardar(long idProgramacion, GuardarViaticosDto? d)
    {
        if (idProgramacion <= 0)
            return (null, "La programación no existe.");
        if (d is null || d.Lineas is null)
            return (null, "Indica la asignación de viáticos.");
        var errVersion = ErrorVersion(d.Version);
        if (errVersion is not null)
            return (null, errVersion);
        if (d.Lineas.Count > MaxLineas)
            return (null, $"Una programación admite hasta {MaxLineas} líneas de viáticos.");

        var vistos = new HashSet<long>();
        var lineas = new List<object>(d.Lineas.Count);
        foreach (var l in d.Lineas)
        {
            if (l is null)
                return (null, "La asignación tiene una línea vacía.");
            if (l.IdTecnico <= 0)
                return (null, "Cada línea debe indicar el técnico.");
            if (l.IdGasto is <= 0)
                return (null, "Hay una línea con un identificador no válido.");
            if (l.IdGasto is { } g && !vistos.Add(g))
                return (null, "Una línea viene repetida en la asignación.");
            if (l.Monto <= 0 || l.Monto > MontoMaximo)
                return (null, "Cada monto debe ser mayor a 0.");
            if (decimal.Round(l.Monto, 2) != l.Monto)
                return (null, "Cada monto admite hasta 2 decimales.");

            var nuevo = l.NuevoConcepto?.Trim();
            if (string.IsNullOrEmpty(nuevo)) nuevo = null;
            if ((l.IdConcepto is null) == (nuevo is null))
                return (null, "Cada línea debe tener un concepto: elige uno del catálogo o crea uno nuevo (no ambos).");
            if (l.IdConcepto is <= 0)
                return (null, "El concepto no es válido.");
            if (nuevo is not null && !NombreConceptoValido(nuevo))
                return (null, "El nombre del concepto nuevo debe tener entre 2 y 60 caracteres: letras, números y signos comunes.");

            lineas.Add(new
            {
                idGasto = l.IdGasto, idTecnico = l.IdTecnico, idConcepto = l.IdConcepto, nuevoConcepto = nuevo,
                monto = l.Monto
            });
        }
        return (new GuardarViaticosNormalizado(d.Version!.Trim(), JsonSerializer.Serialize(lineas)), null);
    }

    internal static (string? Accion, string? Comentario, string? Error) NormalizarRevision(long idProgramacion, long idGasto, RevisarGastoDto? d)
    {
        if (idProgramacion <= 0)
            return (null, null, "La programación no existe.");
        if (idGasto <= 0)
            return (null, null, "El gasto no existe.");
        if (d is null)
            return (null, null, "Indica la acción sobre el gasto.");
        var accion = d.Accion?.Trim().ToLowerInvariant() ?? "";
        if (!Acciones.Contains(accion))
            return (null, null, "La acción debe ser aprobar, observar o rechazar.");
        var comentario = d.Comentario?.Trim();
        var errorTexto = EntradaReprogramacion.ErrorTexto(comentario, MaxComentario, "El comentario");
        if (errorTexto is not null)
            return (null, null, errorTexto);
        if (accion == "observar" && (comentario is null || comentario.Length < 3))
            return (null, null, "Para observar un gasto debes indicar qué debe corregir el técnico.");
        if (accion == "rechazar" && (comentario is null || comentario.Length < 3))
            return (null, null, "Para rechazar un gasto debes indicar el motivo.");
        return (accion, string.IsNullOrEmpty(comentario) ? null : comentario, null);
    }

    internal static string? ErrorIds(long idProgramacion, long? idGasto = null)
        => idProgramacion <= 0 ? "La programación no existe." : idGasto is <= 0 ? "El gasto no existe." : null;

}

/// <summary>Modal "Gestionar Viáticos": asignación (tab 1) y rendición (tab 2). También sirve de referencia de solo lectura (HU-41, Expediente).</summary>
public class ObtenerViaticosProgramacionCasoDeUso(IProgramacionViaticosRepositorio repositorio)
{
    public Task<RespuestaDto<ViaticosProgramacionDto>> EjecutarAsync(long idProgramacion, long idUsuario, CancellationToken ct = default)
    {
        var error = EntradaViaticos.ErrorIds(idProgramacion);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ViaticosProgramacionDto>(1, error))
            : repositorio.ObtenerAsync(idProgramacion, idUsuario, ct);
    }
}

/// <summary>Guarda la asignación y notifica a Contabilidad la lista consolidada de lo pendiente de depósito.</summary>
public class GuardarViaticosProgramacionCasoDeUso(IProgramacionViaticosRepositorio repositorio)
{
    public Task<RespuestaDto<GuardarViaticosResultadoDto>> EjecutarAsync(long idProgramacion, GuardarViaticosDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (n, error) = EntradaViaticos.NormalizarGuardar(idProgramacion, dto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<GuardarViaticosResultadoDto>(1, error))
            : repositorio.GuardarAsync(idProgramacion, n!, idUsuario, ct);
    }
}

/// <summary>Aprobar, observar (comentario obligatorio) o rechazar (motivo obligatorio) un gasto rendido.</summary>
public class RevisarGastoProgramacionCasoDeUso(IProgramacionViaticosRepositorio repositorio)
{
    public Task<RespuestaDto<RevisarGastoResultadoDto>> EjecutarAsync(long idProgramacion, long idGasto, RevisarGastoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (accion, comentario, error) = EntradaViaticos.NormalizarRevision(idProgramacion, idGasto, dto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, error))
            : repositorio.RevisarGastoAsync(idProgramacion, idGasto, accion!, comentario, idUsuario, ct);
    }
}

/// <summary>Cierre de la rendición: saldo final (devolución o reembolso adicional) y aviso a Contabilidad.</summary>
public class CerrarRendicionProgramacionCasoDeUso(IProgramacionViaticosRepositorio repositorio)
{
    public Task<RespuestaDto<CerrarRendicionResultadoDto>> EjecutarAsync(long idProgramacion, long idUsuario, CancellationToken ct = default)
    {
        var error = EntradaViaticos.ErrorIds(idProgramacion);
        return error is not null
            ? Task.FromResult(new RespuestaDto<CerrarRendicionResultadoDto>(1, error))
            : repositorio.CerrarRendicionAsync(idProgramacion, idUsuario, ct);
    }
}

/// <summary>Comprobante de un gasto para el modal secundario.</summary>
public class ObtenerComprobanteGastoCasoDeUso(IProgramacionViaticosRepositorio repositorio)
{
    public Task<RespuestaDto<ComprobanteGastoDto>> EjecutarAsync(long idProgramacion, long idGasto, long idUsuario, CancellationToken ct = default)
    {
        var error = EntradaViaticos.ErrorIds(idProgramacion, idGasto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ComprobanteGastoDto>(1, error))
            : repositorio.ObtenerComprobanteAsync(idProgramacion, idGasto, idUsuario, ct);
    }
}
