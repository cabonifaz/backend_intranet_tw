using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-52 Detalle del Servicio en Ruta (Sprint 5) ──────────────────────────────────────────────────────────

/// <summary>
/// Validación de entrada del detalle. Desarrollo seguro: todo es de SOLO LECTURA; los identificadores deben ser positivos (anti-IDOR: el SP
/// además comprueba que el equipo/registro pertenezca a la OS), categoría/orden/sección de listas cerradas y la clave de incidencia con
/// alfabeto estricto. Los valores viajan como parámetros del SP (nunca se concatena SQL).
/// </summary>
internal static partial class EntradaDetalleServicioRuta
{
    internal static readonly string[] Categorias = ["hito", "alerta", "incidencia", "asistente"];
    internal static readonly string[] Ordenes = ["reciente", "antiguo"];
    internal static readonly string[] Secciones = ["fotos", "ensayos", "documentos", "observaciones", "mediciones"];

    [GeneratedRegex("^[dia][0-9]{1,18}$")]
    private static partial Regex ClaveIncidencia();

    internal static string? ErrorIdOs(long idOs) => idOs <= 0 ? "El servicio indicado no es válido." : null;

    internal static (ConsultaTimelineNormalizada? Datos, string? Error) NormalizarTimeline(string? categoria, string? orden)
    {
        var c = string.IsNullOrWhiteSpace(categoria) ? "" : categoria.Trim().ToLowerInvariant();
        if (c.Length > 0 && !Categorias.Contains(c))
            return (null, "La categoría del timeline no es válida.");
        var o = string.IsNullOrWhiteSpace(orden) ? "reciente" : orden.Trim().ToLowerInvariant();
        if (!Ordenes.Contains(o))
            return (null, "El orden del timeline no es válido.");
        return (new ConsultaTimelineNormalizada(c, o), null);
    }

    internal static (string? Seccion, string? Error) NormalizarSeccion(string? seccion)
    {
        var s = (seccion ?? "").Trim().ToLowerInvariant();
        return Secciones.Contains(s) ? (s, null) : (null, "La sección del equipo no es válida.");
    }

    internal static (string? Clave, string? Error) NormalizarClave(string? clave)
    {
        if (string.IsNullOrWhiteSpace(clave))
            return (null, null);
        var c = clave.Trim().ToLowerInvariant();
        return ClaveIncidencia().IsMatch(c) ? (c, null) : (null, "El registro indicado no es válido.");
    }
}

public class ObtenerDetalleServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleServicioRutaDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<DetalleServicioRutaDto>(1, e)) : repositorio.ObtenerDetalleAsync(idUsuario, idOs, ct);
}

public class ObtenerAvanceServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<AvanceServicioRutaDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<AvanceServicioRutaDto>(1, e)) : repositorio.ObtenerAvanceAsync(idUsuario, idOs, ct);
}

public class ObtenerSeccionEquipoServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<SeccionEquipoRutaDto>> EjecutarAsync(long idUsuario, long idOs, long idEquipo, string? seccion, CancellationToken ct = default)
    {
        if (EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e)
            return Task.FromResult(new RespuestaDto<SeccionEquipoRutaDto>(1, e));
        if (idEquipo <= 0)
            return Task.FromResult(new RespuestaDto<SeccionEquipoRutaDto>(1, "El equipo indicado no es válido."));
        var (s, error) = EntradaDetalleServicioRuta.NormalizarSeccion(seccion);
        return s is null ? Task.FromResult(new RespuestaDto<SeccionEquipoRutaDto>(1, error!)) : repositorio.ObtenerSeccionEquipoAsync(idUsuario, idOs, idEquipo, s, ct);
    }
}

public class ObtenerMapaServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<MapaServicioRutaDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<MapaServicioRutaDto>(1, e)) : repositorio.ObtenerMapaAsync(idUsuario, idOs, ct);
}

public class ObtenerTimelineServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<TimelineServicioRutaDto>> EjecutarAsync(long idUsuario, long idOs, string? categoria, string? orden, CancellationToken ct = default)
    {
        if (EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e)
            return Task.FromResult(new RespuestaDto<TimelineServicioRutaDto>(1, e));
        var (q, error) = EntradaDetalleServicioRuta.NormalizarTimeline(categoria, orden);
        return q is null ? Task.FromResult(new RespuestaDto<TimelineServicioRutaDto>(1, error!)) : repositorio.ObtenerTimelineAsync(idUsuario, idOs, q, ct);
    }
}

/// <summary>Demoras / incidencias de la OS y detalle de un registro (clave opcional).</summary>
public class ObtenerIncidenciasServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<IncidenciasServicioRutaDto>> EjecutarAsync(long idUsuario, long idOs, string? clave, CancellationToken ct = default)
    {
        if (EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e)
            return Task.FromResult(new RespuestaDto<IncidenciasServicioRutaDto>(1, e));
        var (c, error) = EntradaDetalleServicioRuta.NormalizarClave(clave);
        return error is not null ? Task.FromResult(new RespuestaDto<IncidenciasServicioRutaDto>(1, error)) : repositorio.ObtenerIncidenciasAsync(idUsuario, idOs, c, ct);
    }
}

public class ObtenerCierreServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    public Task<RespuestaDto<CierreServicioRutaDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<CierreServicioRutaDto>(1, e)) : repositorio.ObtenerCierreAsync(idUsuario, idOs, ct);
}

/// <summary>
/// Exporta las demoras/incidencias de la OS a CSV. Desarrollo seguro: neutraliza la inyección de fórmulas (celdas que empiezan con = + - @ tab o CR
/// llevan un apóstrofo delante), escapa comillas y saltos de línea, y no incluye la URL de la evidencia (solo Sí/No). UTF-8 con BOM para Excel.
/// </summary>
public class ExportarIncidenciasServicioRutaCasoDeUso(IDetalleServicioRutaRepositorio repositorio)
{
    private static readonly char[] Peligrosos = ['=', '+', '-', '@', '\t', '\r'];

    internal static string Celda(string? valor)
    {
        var t = (valor ?? "").Replace("\r\n", " ").Replace('\n', ' ').Replace('\r', ' ');
        t = new string(t.Where(c => !char.IsControl(c) || c == '\t').ToArray()).Trim();
        if (t.Length > 0 && Peligrosos.Contains(t[0]))
            t = "'" + t;
        return "\"" + t.Replace("\"", "\"\"") + "\"";
    }

    public async Task<RespuestaDto<ArchivoCsvDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        if (EntradaDetalleServicioRuta.ErrorIdOs(idOs) is { } e)
            return new RespuestaDto<ArchivoCsvDto>(1, e);
        var r = await repositorio.ObtenerIncidenciasAsync(idUsuario, idOs, null, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return new RespuestaDto<ArchivoCsvDto>(r.IdTipoMensaje, r.Mensaje);

        var sb = new StringBuilder();
        sb.Append("Hora,Tipo,Descripción,Duración (min),Impacto,Origen,Registrado por,Evidencia\r\n");
        foreach (var f in r.Datos.Filas)
            sb.Append(string.Join(',', Celda(f.Hora), Celda(f.Tipo), Celda(f.Descripcion), Celda(f.DuracionMin?.ToString(CultureInfo.InvariantCulture)),
                Celda(f.Impacto == "detiene" ? "Detiene" : "Retrasa"), Celda(f.Origen == "asistente" ? "Asistente" : "Técnico"), Celda(f.Registrador),
                Celda(f.TieneEvidencia ? "Sí" : "No"))).Append("\r\n");
        var bytes = new UTF8Encoding(true).GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
        return new RespuestaDto<ArchivoCsvDto>(2, "OK", new ArchivoCsvDto($"incidencias-servicio-{idOs}.csv", bytes));
    }
}
