using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerResumenDashboardCasoDeUso(IDashboardRepositorio repositorio)
{
    public async Task<RespuestaDto<KpisDashboardDto>> EjecutarAsync(CancellationToken ct = default)
        => await repositorio.ObtenerResumenAsync(ct);
}
