using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ══════════════════════ HU-17 — Bandeja de Seguimiento Comercial ══════════════════════

public class ObtenerBandejaSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    private static readonly string[] Estados =
    [
        "", "abiertas", "en_seguimiento", "sin_respuesta", "requiere_ajuste", "vencidos",
        "aceptada", "rechazada", "oc_pendientes", "aceptadas_mes", "rechazadas_mes", "todas",
    ];

    public Task<RespuestaDto<BandejaSeguimientoDto>> EjecutarAsync(
        FiltrosBandejaSeguimientoDto f, long idUsuario, CancellationToken ct = default)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return Task.FromResult(new RespuestaDto<BandejaSeguimientoDto>(1,
                "Estado no válido. Use abiertas, en_seguimiento, sin_respuesta, requiere_ajuste, vencidos, " +
                "aceptada, rechazada, oc_pendientes, aceptadas_mes, rechazadas_mes o todas."));

        var filtros = f with
        {
            IdResponsable = f.IdResponsable is > 0 ? f.IdResponsable : null,
            Estado        = estado,
            Busqueda      = string.IsNullOrWhiteSpace(f.Busqueda) ? null : f.Busqueda.Trim(),
            Pagina        = Math.Max(f.Pagina, 1),
            PorPagina     = Math.Clamp(f.PorPagina, 1, 100),
        };
        return repositorio.ObtenerBandejaAsync(filtros, idUsuario, ct);
    }
}

// ══════════════════════ HU-18 — Vista Detalle del Seguimiento ══════════════════════

public class ObtenerDetalleSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleSeguimientoDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<DetalleSeguimientoDto>(1, "Propuesta no válida."));
        return repositorio.ObtenerDetalleAsync(idPropuesta, idUsuario, ct);
    }
}
