using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class CambiarEstadoTextoBaseCasoDeUso(ITextosBaseRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(
        CambiarEstadoTextoBaseDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Estado))
            return Task.FromResult(new RespuestaDto<object>(1, "El estado es obligatorio."));

        return repositorio.CambiarEstadoTextoBaseAsync(dto.IdTextoBase, dto.Estado, idUsuario, ct);
    }
}
