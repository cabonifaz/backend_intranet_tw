using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerTextoBasePorIdCasoDeUso(ITextosBaseRepositorio repositorio)
{
    public Task<RespuestaDto<TextoBaseDetalleDto>> EjecutarAsync(long idTextoBase, CancellationToken ct = default)
        => repositorio.ObtenerTextoBasePorIdAsync(idTextoBase, ct);
}
