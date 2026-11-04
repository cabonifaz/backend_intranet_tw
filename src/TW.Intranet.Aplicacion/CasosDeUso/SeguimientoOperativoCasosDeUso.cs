using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-51 Bandeja de Seguimiento Operativo (Sprint 5) ──────────────────────────────────────────────────────────

/// <summary>
/// Validación de los filtros de la bandeja. Desarrollo seguro: la bandeja es de SOLO LECTURA; aun así todo filtro se valida antes de
/// llegar al SP: identificadores positivos, estado/rango/impacto de lista cerrada, tipo con alfabeto estricto (código del catálogo),
/// zona y búsqueda con largo máximo y sin caracteres de control, paginación acotada. Los valores viajan como parámetros del SP
/// (nunca se concatena SQL) y el SP los vuelve a validar.
/// </summary>
internal static partial class EntradaSeguimiento
{
    internal const int MaxTexto = 100;
    internal const int TamanoPorDefecto = 8;
    internal const int TamanoMaximo = 50;
    internal static readonly string[] Estados = ["sin_salir", "en_ruta", "en_planta", "en_ejecucion", "con_demora", "con_incidente", "finalizado"];
    internal static readonly string[] Rangos = ["en_curso", "finalizados", "sin_iniciar"];
    internal static readonly string[] Impactos = ["retrasa", "detiene"];

    [GeneratedRegex("^[A-Z0-9_]{1,40}$")]
    private static partial Regex CodigoTipo();

    private static string? ErrorTextoFiltro(string? t, string campo)
    {
        if (t is null)
            return null;
        if (t.Length > MaxTexto)
            return $"{campo} no puede superar {MaxTexto} caracteres.";
        if (t.Any(char.IsControl))
            return $"{campo} contiene caracteres no válidos.";
        return null;
    }

    internal static (ConsultaSeguimientoNormalizada? Datos, string? Error) Normalizar(ConsultaSeguimientoDto? d)
    {
        d ??= new ConsultaSeguimientoDto();
        if (d.IdTecnico is <= 0 || d.IdCliente is <= 0)
            return (null, "El técnico o el cliente del filtro no es válido.");

        var estado = string.IsNullOrWhiteSpace(d.Estado) ? null : d.Estado.Trim().ToLowerInvariant();
        if (estado is not null && !Estados.Contains(estado))
            return (null, "El estado del servicio no es válido.");

        var rango = string.IsNullOrWhiteSpace(d.Rango) ? null : d.Rango.Trim().ToLowerInvariant();
        if (rango is not null && !Rangos.Contains(rango))
            return (null, "El rango de estado no es válido.");

        var impacto = string.IsNullOrWhiteSpace(d.Impacto) ? null : d.Impacto.Trim().ToLowerInvariant();
        if (impacto is not null && !Impactos.Contains(impacto))
            return (null, "El impacto no es válido.");

        var tipo = string.IsNullOrWhiteSpace(d.Tipo) ? null : d.Tipo.Trim().ToUpperInvariant();
        if (tipo is not null && !CodigoTipo().IsMatch(tipo))
            return (null, "El tipo de incidencia no es válido.");

        var zona = string.IsNullOrWhiteSpace(d.Zona) ? null : d.Zona.Trim();
        var busqueda = string.IsNullOrWhiteSpace(d.Busqueda) ? null : d.Busqueda.Trim();
        var error = ErrorTextoFiltro(zona, "La zona") ?? ErrorTextoFiltro(busqueda, "La búsqueda");
        if (error is not null)
            return (null, error);

        var pagina = d.Pagina ?? 1;
        var tamano = d.Tamano ?? TamanoPorDefecto;
        if (pagina < 1 || pagina > 10_000 || tamano < 1 || tamano > TamanoMaximo)
            return (null, $"La paginación no es válida (página desde 1, tamaño de 1 a {TamanoMaximo}).");

        return (new ConsultaSeguimientoNormalizada(d.IdTecnico, d.IdCliente, estado, zona, busqueda, rango, pagina, tamano, tipo, impacto), null);
    }
}

/// <summary>KPIs superiores y pestaña 1 Vista Principal (mapa operativo, alertas críticas y próximos hitos esperados).</summary>
public class ObtenerResumenSeguimientoCasoDeUso(ISeguimientoOperativoRepositorio repositorio)
{
    public Task<RespuestaDto<ResumenSeguimientoDto>> EjecutarAsync(ConsultaSeguimientoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (q, error) = EntradaSeguimiento.Normalizar(dto);
        return q is null ? Task.FromResult(new RespuestaDto<ResumenSeguimientoDto>(1, error!)) : repositorio.ObtenerResumenAsync(q, idUsuario, ct);
    }
}

/// <summary>Pestaña 2 Servicios en Campo (filtros, rango de estado y paginación).</summary>
public class ObtenerServiciosSeguimientoCasoDeUso(ISeguimientoOperativoRepositorio repositorio)
{
    public Task<RespuestaDto<ServiciosSeguimientoDto>> EjecutarAsync(ConsultaSeguimientoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (q, error) = EntradaSeguimiento.Normalizar(dto);
        return q is null ? Task.FromResult(new RespuestaDto<ServiciosSeguimientoDto>(1, error!)) : repositorio.ObtenerServiciosAsync(q, idUsuario, ct);
    }
}

/// <summary>Pestaña 3 Técnicos Activos.</summary>
public class ObtenerTecnicosSeguimientoCasoDeUso(ISeguimientoOperativoRepositorio repositorio)
{
    public Task<RespuestaDto<TecnicosSeguimientoDto>> EjecutarAsync(ConsultaSeguimientoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (q, error) = EntradaSeguimiento.Normalizar(dto);
        return q is null ? Task.FromResult(new RespuestaDto<TecnicosSeguimientoDto>(1, error!)) : repositorio.ObtenerTecnicosAsync(q, idUsuario, ct);
    }
}

/// <summary>Pestaña 4 Incidencias del Día.</summary>
public class ObtenerIncidenciasSeguimientoCasoDeUso(ISeguimientoOperativoRepositorio repositorio)
{
    public Task<RespuestaDto<IncidenciasSeguimientoDto>> EjecutarAsync(ConsultaSeguimientoDto? dto, long idUsuario, CancellationToken ct = default)
    {
        var (q, error) = EntradaSeguimiento.Normalizar(dto);
        return q is null ? Task.FromResult(new RespuestaDto<IncidenciasSeguimientoDto>(1, error!)) : repositorio.ObtenerIncidenciasAsync(q, idUsuario, ct);
    }
}

/// <summary>Opciones de los filtros globales.</summary>
public class ObtenerFiltrosSeguimientoCasoDeUso(ISeguimientoOperativoRepositorio repositorio)
{
    public Task<RespuestaDto<OpcionesFiltrosSeguimientoDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => repositorio.ObtenerFiltrosAsync(idUsuario, ct);
}

/// <summary>
/// App móvil: registra la posición GPS del técnico (alimenta la bandeja). Desarrollo seguro: el usuario sale del token (nunca del cuerpo), la OS
/// debe ser suya, coordenadas dentro de rango y distintas de (0,0), precisión acotada. El SP vuelve a validar todo y aplica antirrebote de 10 s.
/// </summary>
public class RegistrarUbicacionMovilCasoDeUso(ISeguimientoOperativoRepositorio repositorio)
{
    public Task<RespuestaDto<UbicacionRegistradaDto>> EjecutarAsync(long idUsuario, long idOs, RegistrarUbicacionDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return Task.FromResult(new RespuestaDto<UbicacionRegistradaDto>(1, "Servicio no encontrado o no asignado a tu usuario."));
        if (d?.Latitud is not { } lat || d.Longitud is not { } lon || lat is < -90m or > 90m || lon is < -180m or > 180m || (lat == 0m && lon == 0m))
            return Task.FromResult(new RespuestaDto<UbicacionRegistradaDto>(1, "La ubicación no es válida."));
        if (d.PrecisionMetros is < 0m or > 5000m)
            return Task.FromResult(new RespuestaDto<UbicacionRegistradaDto>(1, "La precisión de la ubicación no es válida."));
        return repositorio.RegistrarUbicacionAsync(idUsuario, idOs, Math.Round(lat, 7), Math.Round(lon, 7), d.PrecisionMetros is { } p ? Math.Round(p, 1) : null, ct);
    }
}
