using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerRequerimientosCasoDeUso(ICrmRepositorio repo)
{
    public Task<RespuestaDto<RequerimientosPaginadoDto>> EjecutarAsync(
        string? estado, string? busqueda, int pagina, int porPagina,
        long idUsuario, string rol, CancellationToken ct)
        => repo.ObtenerRequerimientosAsync(
            estado, busqueda, pagina, porPagina, idUsuario, rol, ct);
}