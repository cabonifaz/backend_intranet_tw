using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-29 / HU-30 — Panel de campo en tiempo real y Seguimiento del servicio ─────────────────────────────
// El alcance (área de la RQ para Servicio Técnico y Metrología; las demás áreas ven todo), el estado de cada servicio y las reglas del cambio de estado viven en
// los procedimientos (SP_ResolverJefaturaMovil, SP_ArmarAlcanceJefaturaMovil y el seguimiento operativo HU-51/53). Aquí solo se valida la entrada.

/// <summary>Validación de la entrada del Panel de Campo (pública y sin dependencias: se prueba sin base de datos).</summary>
public static class ValidacionPanelCampo
{
    public static readonly string[] Filtros = ["activos", "demora", "incidencias", "finalizados"];
    public static readonly string[] Estados = ["salida", "en_ruta", "llegada", "ingreso", "inicio", "finalizado"];
    public const int MaxBusqueda = 100;
    public const int MinComentario = 10;
    public const int MaxComentario = 1000;
    public const int MinAviso = 5;
    public const int MaxAviso = 450;

    /// <summary>Filtro de "Servicios activos": vacío = activos. Otro valor distinto de los permitidos → null.</summary>
    public static string? NormalizarFiltro(string? filtro)
    {
        var f = string.IsNullOrWhiteSpace(filtro) ? "activos" : filtro.Trim().ToLowerInvariant();
        return Filtros.Contains(f) ? f : null;
    }

    /// <summary>Búsqueda recortada; null si supera el máximo. Vacía → null (sin búsqueda).</summary>
    public static (bool Valida, string? Texto) NormalizarBusqueda(string? busqueda)
    {
        var t = busqueda?.Trim();
        if (string.IsNullOrEmpty(t)) return (true, null);
        return t.Length > MaxBusqueda ? (false, null) : (true, t);
    }

    public static string? ErrorCambioEstado(CambiarEstadoServicioDto? d)
    {
        if (d is null) return "Indica el nuevo estado, el motivo y el comentario.";
        if (string.IsNullOrWhiteSpace(d.NuevoEstado) || !Estados.Contains(d.NuevoEstado.Trim())) return "El nuevo estado no es válido.";
        if (d.IdMotivo is null or <= 0) return "Elige el motivo del cambio.";
        var c = d.Comentario?.Trim() ?? string.Empty;
        if (c.Length < MinComentario) return $"El comentario es obligatorio (mínimo {MinComentario} caracteres).";
        if (c.Length > MaxComentario) return $"El comentario no puede superar los {MaxComentario} caracteres.";
        return null;
    }

    public static string? ErrorAviso(AvisarClienteDto? d)
    {
        var m = d?.Mensaje?.Trim() ?? string.Empty;
        if (m.Length < MinAviso) return $"Escribe lo que se le avisó al cliente (mínimo {MinAviso} caracteres).";
        if (m.Length > MaxAviso) return $"El aviso no puede superar los {MaxAviso} caracteres.";
        return null;
    }
}

/// <summary>Panel de Campo: KPIs, pines del mapa por técnico y alertas críticas (HU-29).</summary>
public class ObtenerPanelCampoMovilCasoDeUso(IPanelCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<PanelCampoDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<PanelCampoDto>(1, "No se pudo identificar al usuario."))
            : repositorio.ObtenerPanelAsync(idUsuario, ct);
}

/// <summary>Servicios activos (vista lista del Panel de Campo): búsqueda por OS, cliente o técnico y filtros (HU-29).</summary>
public class ObtenerServiciosJefaturaMovilCasoDeUso(IPanelCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ServiciosJefaturaDto>> EjecutarAsync(long idUsuario, string? filtro, string? busqueda, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<ServiciosJefaturaDto>(1, "No se pudo identificar al usuario."));
        var f = ValidacionPanelCampo.NormalizarFiltro(filtro);
        if (f is null)
            return Task.FromResult(new RespuestaDto<ServiciosJefaturaDto>(1, "El filtro de servicios no es válido."));
        var (valida, texto) = ValidacionPanelCampo.NormalizarBusqueda(busqueda);
        if (!valida)
            return Task.FromResult(new RespuestaDto<ServiciosJefaturaDto>(1, $"La búsqueda no puede superar los {ValidacionPanelCampo.MaxBusqueda} caracteres."));
        return repositorio.ObtenerServiciosAsync(idUsuario, f, texto, ct);
    }
}

/// <summary>Detalle de un servicio: técnico, estado, hitos y opciones del cambio de estado (HU-30).</summary>
public class ObtenerServicioJefaturaMovilCasoDeUso(IPanelCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ServicioJefaturaDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<ServicioJefaturaDto>(1, "No se pudo identificar al usuario."))
        : idOs <= 0    ? Task.FromResult(new RespuestaDto<ServicioJefaturaDto>(1, "El servicio indicado no es válido."))
        : repositorio.ObtenerServicioAsync(idUsuario, idOs, ct);
}

/// <summary>Ubicación y ruta del técnico en un servicio (HU-30).</summary>
public class ObtenerRutaServicioJefaturaMovilCasoDeUso(IPanelCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<RutaServicioDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<RutaServicioDto>(1, "No se pudo identificar al usuario."))
        : idOs <= 0    ? Task.FromResult(new RespuestaDto<RutaServicioDto>(1, "El servicio indicado no es válido."))
        : repositorio.ObtenerRutaAsync(idUsuario, idOs, ct);
}

/// <summary>
/// Cambio manual de estado del servicio (solo con motivo y comentario; queda en el historial con el usuario y la hora) y constancia del aviso al cliente (HU-30).
/// El SP delega en el registro del Asistente de Seguimiento (HU-53): permisos, "solo avanzar", auditoría y notificaciones se resuelven allí, una sola vez.
/// </summary>
public class RegistrarSeguimientoJefaturaMovilCasoDeUso(IPanelCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<RegistroSeguimientoResultadoDto>> CambiarEstadoAsync(long idUsuario, long idOs, CambiarEstadoServicioDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<RegistroSeguimientoResultadoDto>(1, "No se pudo identificar al usuario."));
        if (idOs <= 0)
            return Task.FromResult(new RespuestaDto<RegistroSeguimientoResultadoDto>(1, "El servicio indicado no es válido."));
        var error = ValidacionPanelCampo.ErrorCambioEstado(d);
        if (error is not null)
            return Task.FromResult(new RespuestaDto<RegistroSeguimientoResultadoDto>(1, error));
        return repositorio.RegistrarAsync(idUsuario, idOs, "cambio_estado", d!.NuevoEstado!.Trim(), d.IdMotivo, d.Comentario!.Trim(), ct);
    }

    public Task<RespuestaDto<RegistroSeguimientoResultadoDto>> AvisarClienteAsync(long idUsuario, long idOs, AvisarClienteDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<RegistroSeguimientoResultadoDto>(1, "No se pudo identificar al usuario."));
        if (idOs <= 0)
            return Task.FromResult(new RespuestaDto<RegistroSeguimientoResultadoDto>(1, "El servicio indicado no es válido."));
        var error = ValidacionPanelCampo.ErrorAviso(d);
        if (error is not null)
            return Task.FromResult(new RespuestaDto<RegistroSeguimientoResultadoDto>(1, error));
        return repositorio.RegistrarAsync(idUsuario, idOs, "aviso_cliente", null, null, d!.Mensaje!.Trim(), ct);
    }
}
