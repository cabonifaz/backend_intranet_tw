using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerProcedimientosCasoDeUso(IProcedimientosRepositorio repositorio)
{
    public Task<RespuestaDto<ProcedimientosPaginadoDto>> EjecutarAsync(
        string? busqueda, int? anio, string? estado, int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerProcedimientosAsync(
            busqueda, anio, estado, Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 100), ct);
}
