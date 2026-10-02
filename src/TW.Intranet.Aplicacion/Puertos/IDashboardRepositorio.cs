using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IDashboardRepositorio
{
    Task<RespuestaDto<KpisDashboardDto>>        ObtenerResumenAsync(CancellationToken ct);
    Task<RespuestaDto<List<AlertaOperativaDto>>> ObtenerAlertasAsync(CancellationToken ct);
}
