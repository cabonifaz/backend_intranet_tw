using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerSuplentesCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<SuplentesPaginadoDto>> EjecutarAsync(
        string? busqueda, string? estado, int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerSuplentesAsync(
            busqueda, estado, Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
