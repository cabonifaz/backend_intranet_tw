using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerPropuestasCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<PropuestasPaginadoDto>> EjecutarAsync(
        long? idRequerimiento, string? estado, string? busqueda, int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerPropuestasAsync(
            idRequerimiento, estado, busqueda, Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
