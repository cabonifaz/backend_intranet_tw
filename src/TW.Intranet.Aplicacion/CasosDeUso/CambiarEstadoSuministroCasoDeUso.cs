using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoSuministroCasoDeUso(ISuministrosRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoSuministroDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Estado))
            return Task.FromResult(new RespuestaDto<object>(1, "El estado es obligatorio."));

        return repositorio.CambiarEstadoSuministroAsync(dto.IdSuministro, dto.Estado, idUsuario, ct);
    }
}
