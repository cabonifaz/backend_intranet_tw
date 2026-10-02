using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerEquipoClientePorIdCasoDeUso(IEquiposClienteRepositorio repositorio)
{
    public Task<RespuestaDto<EquipoClienteDetalleDto>> EjecutarAsync(long idEquipo, CancellationToken ct = default)
        => repositorio.ObtenerEquipoPorIdAsync(idEquipo, ct);
}
