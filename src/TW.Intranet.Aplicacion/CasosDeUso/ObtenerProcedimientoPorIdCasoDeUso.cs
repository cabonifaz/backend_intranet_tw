using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerProcedimientoPorIdCasoDeUso(IProcedimientosRepositorio repositorio)
{
    public Task<RespuestaDto<ProcedimientoDetalleDto>> EjecutarAsync(long idProcedimiento, CancellationToken ct = default)
        => repositorio.ObtenerProcedimientoPorIdAsync(idProcedimiento, ct);
}
