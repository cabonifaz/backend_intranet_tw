using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerCategoriasCasoDeUso(IMaestrosRepositorio repositorio)
{
    public Task<RespuestaDto<List<CategoriaClienteDto>>> EjecutarAsync(CancellationToken ct = default)
        => repositorio.ObtenerCategoriasAsync(ct);
}
