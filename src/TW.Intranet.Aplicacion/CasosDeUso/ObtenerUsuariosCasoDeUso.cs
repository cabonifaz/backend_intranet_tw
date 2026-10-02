using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerUsuariosCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<UsuariosPaginadoDto>> EjecutarAsync(
        string? busqueda, string? rol, string? estado, int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerUsuariosAsync(
            busqueda, rol, estado, Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
