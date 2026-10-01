using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoUsuarioCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoUsuarioDto dto, long idEjecutor, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Estado))
            return Task.FromResult(new RespuestaDto<object>(1, "El estado es obligatorio."));

        return repositorio.CambiarEstadoUsuarioAsync(dto.IdUsuario, dto.Estado, idEjecutor, ct);
    }
}
