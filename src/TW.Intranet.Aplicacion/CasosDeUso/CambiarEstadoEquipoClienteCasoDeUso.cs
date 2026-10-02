using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoEquipoClienteCasoDeUso(IEquiposClienteRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoEquipoClienteDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Estado))
            return Task.FromResult(new RespuestaDto<object>(1, "El estado es obligatorio."));

        return repositorio.CambiarEstadoEquipoAsync(dto.IdEquipo, dto.Estado, idUsuario, ct);
    }
}
