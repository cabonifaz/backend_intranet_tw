using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerSuministrosCasoDeUso(ISuministrosRepositorio repositorio)
{
    public Task<RespuestaDto<SuministrosPaginadoDto>> EjecutarAsync(
        string? busqueda, string? clase, string? tipo, string? estado, bool soloEnPropuestas,
        int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerSuministrosAsync(
            busqueda, clase, tipo, estado, soloEnPropuestas,
            Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
