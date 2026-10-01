using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoProcedimientoCasoDeUso(IProcedimientosRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoProcedimientoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Estado))
            return Task.FromResult(new RespuestaDto<object>(1, "El estado es obligatorio."));

        return repositorio.CambiarEstadoProcedimientoAsync(dto.IdProcedimiento, dto.Estado, idUsuario, ct);
    }
}
