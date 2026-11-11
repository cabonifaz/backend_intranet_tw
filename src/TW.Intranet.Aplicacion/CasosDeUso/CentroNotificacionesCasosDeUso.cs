using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-90 Centro de Notificaciones del Usuario (Sprint 5, Módulo 16) ─────────────────────────────────────────────
// Módulo transversal: todos los usuarios de la intranet; cada uno ve SOLO sus notificaciones (el id sale del token y
// cada SP filtra por id_usuario_destino). Las notificaciones las generan los demás módulos.

/// <summary>Campana del header: badge de no leídas + las 5 últimas no leídas.</summary>
public class ObtenerResumenNotificacionesCasoDeUso(INotificacionesRepositorio repositorio)
{
    public Task<RespuestaDto<ResumenNotificacionesDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => repositorio.ObtenerResumenAsync(idUsuario, ct);
}

/// <summary>Bandeja completa (/notificaciones) con filtros y paginado.</summary>
public class ObtenerBandejaNotificacionesCasoDeUso(INotificacionesRepositorio repositorio)
{
    public Task<RespuestaDto<BandejaNotificacionesDto>> EjecutarAsync(FiltrosBandejaNotificacionesDto f, long idUsuario, CancellationToken ct = default)
    {
        var error = Normalizar(f);
        return error is not null
            ? Task.FromResult(new RespuestaDto<BandejaNotificacionesDto>(1, error))
            : repositorio.ObtenerBandejaAsync(f, idUsuario, ct);
    }

    internal static string? Normalizar(FiltrosBandejaNotificacionesDto f)
    {
        f.Estado = string.IsNullOrWhiteSpace(f.Estado) ? null : f.Estado.Trim().ToLowerInvariant();
        if (f.Estado is not null && !ValidacionNotificaciones.EsValido(CatalogoNotificaciones.Estados, f.Estado))
            return $"Estado no válido. Use: {ValidacionNotificaciones.Lista(CatalogoNotificaciones.Estados)}.";

        var (modulos, moduloInvalido) = ValidacionNotificaciones.NormalizarLista(f.Modulos, CatalogoNotificaciones.Modulos);
        if (moduloInvalido is not null)
            return $"Módulo no válido: {moduloInvalido}. Use: {ValidacionNotificaciones.Lista(CatalogoNotificaciones.Modulos)}.";
        f.Modulos = modulos;

        var (tipos, tipoInvalido) = ValidacionNotificaciones.NormalizarLista(f.Tipos, CatalogoNotificaciones.Tipos);
        if (tipoInvalido is not null)
            return $"Tipo no válido: {tipoInvalido}. Use: {ValidacionNotificaciones.Lista(CatalogoNotificaciones.Tipos)}.";
        f.Tipos = tipos;

        f.Rango = string.IsNullOrWhiteSpace(f.Rango) || f.Rango.Trim().Equals("todas", StringComparison.OrdinalIgnoreCase)
            ? null : f.Rango.Trim().ToLowerInvariant();
        if (f.Rango is not null && !ValidacionNotificaciones.EsValido(CatalogoNotificaciones.Rangos, f.Rango))
            return $"Rango de fecha no válido. Use: {ValidacionNotificaciones.Lista(CatalogoNotificaciones.Rangos)}.";

        if (f.Rango == "custom")
        {
            if (f.FechaDesde is null && f.FechaHasta is null)
                return "Para el rango personalizado indica la fecha desde o la fecha hasta.";
            if (f.FechaDesde is { } d && f.FechaHasta is { } h && d.Date > h.Date)
                return "La fecha desde no puede ser posterior a la fecha hasta.";
        }
        else
        {
            // Las fechas solo aplican al rango personalizado
            f.FechaDesde = null;
            f.FechaHasta = null;
        }

        if (f.Remitente is < 0)
            return "Remitente no válido.";

        var busqueda = f.Busqueda?.Trim();
        f.Busqueda  = string.IsNullOrEmpty(busqueda) ? null : (busqueda.Length > 200 ? busqueda[..200] : busqueda);
        f.Pagina    = Math.Clamp(f.Pagina, 1, 10000);
        f.PorPagina = f.PorPagina is < 1 or > 100 ? 30 : f.PorPagina;
        return null;
    }
}

/// <summary>Panel de detalle: devuelve la notificación y la marca como leída (HU: "al abrirla se marca automáticamente").</summary>
public class ObtenerDetalleNotificacionCasoDeUso(INotificacionesRepositorio repositorio, INotificadorTiempoReal notificador)
{
    public async Task<RespuestaDto<DetalleNotificacionDto>> EjecutarAsync(long idNotificacion, long idUsuario, CancellationToken ct = default)
    {
        if (idNotificacion <= 0) return new RespuestaDto<DetalleNotificacionDto>(1, "Notificación no encontrada.");

        var r = await repositorio.ObtenerDetalleAsync(idNotificacion, idUsuario, ct);
        if (r.IdTipoMensaje == 2 && r.Datos is { } d)
            await notificador.NotificacionActualizadaAsync(idUsuario, [idNotificacion], false, "leida", d.NoLeidas);
        return r;
    }
}

/// <summary>"Marcar las 5 como leídas" (ids del popover) o "Marcar todas como leídas" (todas = true).</summary>
public class MarcarNotificacionesLeidasCasoDeUso(INotificacionesRepositorio repositorio, INotificadorTiempoReal notificador)
{
    public const int MaximoIds = 100;

    public async Task<RespuestaDto<ResultadoMarcadoNotificacionesDto>> EjecutarAsync(MarcarNotificacionesLeidasDto? datos, long idUsuario, CancellationToken ct = default)
    {
        if (datos is null)
            return new RespuestaDto<ResultadoMarcadoNotificacionesDto>(1, "Indica las notificaciones a marcar o marca todas.");

        List<long> ids = datos.Todas ? [] : (datos.Ids ?? []).Where(id => id > 0).Distinct().ToList();
        if (!datos.Todas && ids.Count == 0)
            return new RespuestaDto<ResultadoMarcadoNotificacionesDto>(1, "Indica las notificaciones a marcar o marca todas.");
        if (ids.Count > MaximoIds)
            return new RespuestaDto<ResultadoMarcadoNotificacionesDto>(1, $"Puedes marcar como máximo {MaximoIds} notificaciones a la vez.");

        var r = await repositorio.MarcarLeidasAsync(ids, datos.Todas, idUsuario, ct);
        if (r.IdTipoMensaje == 2 && r.Datos is { Marcadas: > 0 } d)
            await notificador.NotificacionActualizadaAsync(idUsuario, ids, datos.Todas, "leida", d.NoLeidas);
        return r;
    }
}

/// <summary>"Archivar": solo notificaciones leídas. Quedan accesibles en el filtro "archivadas".</summary>
public class ArchivarNotificacionCasoDeUso(INotificacionesRepositorio repositorio, INotificadorTiempoReal notificador)
{
    public async Task<RespuestaDto<ResultadoArchivadoNotificacionDto>> EjecutarAsync(long idNotificacion, long idUsuario, CancellationToken ct = default)
    {
        if (idNotificacion <= 0) return new RespuestaDto<ResultadoArchivadoNotificacionDto>(1, "Notificación no encontrada.");

        var r = await repositorio.ArchivarAsync(idNotificacion, idUsuario, ct);
        if (r.IdTipoMensaje == 2 && r.Datos is { } d)
            await notificador.NotificacionActualizadaAsync(idUsuario, [idNotificacion], false, "archivada", d.NoLeidas);
        return r;
    }
}

/// <summary>Opciones de los filtros de la bandeja: catálogo completo con los conteos del usuario y sus remitentes.</summary>
public class ObtenerFiltrosNotificacionesCasoDeUso(INotificacionesRepositorio repositorio)
{
    public async Task<RespuestaDto<FiltrosNotificacionesDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        var r = await repositorio.ObtenerConteosFiltrosAsync(idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return new RespuestaDto<FiltrosNotificacionesDto>(r.IdTipoMensaje, r.Mensaje);

        static List<OpcionFiltroNotificacionDto> Completar(
            IReadOnlyList<(string Valor, string Etiqueta)> catalogo, List<ConteoFiltroNotificacionDto> conteos)
            => catalogo.Select(c =>
            {
                var n = conteos.FirstOrDefault(x => string.Equals(x.Valor, c.Valor, StringComparison.OrdinalIgnoreCase));
                return new OpcionFiltroNotificacionDto(c.Valor, c.Etiqueta, n?.Total ?? 0, n?.NoLeidas ?? 0);
            }).ToList();

        return new RespuestaDto<FiltrosNotificacionesDto>(2, r.Mensaje, new FiltrosNotificacionesDto(
            Modulos:    Completar(CatalogoNotificaciones.Modulos, r.Datos.Modulos),
            Tipos:      Completar(CatalogoNotificaciones.Tipos,   r.Datos.Tipos),
            Estados:    CatalogoNotificaciones.Estados.Select(e => new OpcionFiltroNotificacionDto(e.Valor, e.Etiqueta, 0, 0)).ToList(),
            Rangos:     CatalogoNotificaciones.Rangos.Select(e => new OpcionFiltroNotificacionDto(e.Valor, e.Etiqueta, 0, 0)).ToList(),
            Remitentes: r.Datos.Remitentes));
    }
}

/// <summary>Worker: guarda las alertas operativas del Módulo 11 como notificaciones (para quienes tienen seg_bandeja).</summary>
public class GenerarAlertasOperativasCasoDeUso(INotificacionesRepositorio repositorio)
{
    public Task<RespuestaDto<ResultadoAlertasOperativasDto>> EjecutarAsync(CancellationToken ct = default)
        => repositorio.GenerarAlertasOperativasAsync(ct);
}

/// <summary>HU-90 parte 2 — Worker de tiempo real: notificaciones insertadas por cualquier SP con id &gt; desdeId (máx. limite).
/// desdeId &lt; 0 = solo inicializar (devuelve el último id, sin filas).</summary>
public class ObtenerNotificacionesNuevasCasoDeUso(INotificacionesRepositorio repositorio)
{
    public Task<RespuestaDto<NotificacionesNuevasDto>> EjecutarAsync(long desdeId, int limite, CancellationToken ct = default)
        => repositorio.ObtenerNuevasAsync(desdeId, Math.Clamp(limite, 1, 5000), ct);
}

internal static class ValidacionNotificaciones
{
    public static bool EsValido(IReadOnlyList<(string Valor, string Etiqueta)> catalogo, string valor)
        => catalogo.Any(c => c.Valor == valor);

    public static string Lista(IReadOnlyList<(string Valor, string Etiqueta)> catalogo)
        => string.Join(", ", catalogo.Select(c => c.Valor));

    /// <summary>"a, B ,a" → "a,b" (solo valores del catálogo). Devuelve el primer valor inválido, si hay.</summary>
    public static (string? Normalizada, string? Invalido) NormalizarLista(string? csv, IReadOnlyList<(string Valor, string Etiqueta)> catalogo)
    {
        if (string.IsNullOrWhiteSpace(csv)) return (null, null);

        var valores = csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                         .Select(v => v.ToLowerInvariant())
                         .Distinct()
                         .ToList();
        var invalido = valores.FirstOrDefault(v => !EsValido(catalogo, v));
        if (invalido is not null) return (null, invalido.Length > 40 ? invalido[..40] : invalido);

        return (valores.Count == 0 ? null : string.Join(',', valores), null);
    }
}
