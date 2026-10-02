using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerTextosBaseCasoDeUso(ITextosBaseRepositorio repositorio)
{
    public Task<RespuestaDto<TextosBasePaginadoDto>> EjecutarAsync(
        string? busqueda, string? tipoCategoria, string? estado, bool soloPredeterminados,
        int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerTextosBaseAsync(
            busqueda, tipoCategoria, estado, soloPredeterminados,
            Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
