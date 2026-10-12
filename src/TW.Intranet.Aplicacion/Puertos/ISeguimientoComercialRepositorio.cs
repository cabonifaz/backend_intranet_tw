using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-17 — Seguimiento comercial de propuestas enviadas.</summary>
public interface ISeguimientoComercialRepositorio
{
    Task<RespuestaDto<BandejaSeguimientoDto>> ObtenerBandejaAsync(FiltrosBandejaSeguimientoDto f, long idUsuario, CancellationToken ct);
}
