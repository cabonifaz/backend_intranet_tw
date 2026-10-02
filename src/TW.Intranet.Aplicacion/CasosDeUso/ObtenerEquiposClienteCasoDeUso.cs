using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerEquiposClienteCasoDeUso(IEquiposClienteRepositorio repositorio)
{
    public Task<RespuestaDto<EquiposClientePaginadoDto>> EjecutarAsync(
        string? busqueda, long? idCliente, long? idSede,
        string? clasificacion, string? estado, bool soloVigentesServicio,
        int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerEquiposAsync(
            busqueda, idCliente, idSede, clasificacion, estado, soloVigentesServicio,
            Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
