using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerAlertasOperativasCasoDeUso(IDashboardRepositorio repositorio)
{
    public async Task<RespuestaDto<List<AlertaOperativaDto>>> EjecutarAsync(CancellationToken ct = default)
        => await repositorio.ObtenerAlertasAsync(ct);
}
