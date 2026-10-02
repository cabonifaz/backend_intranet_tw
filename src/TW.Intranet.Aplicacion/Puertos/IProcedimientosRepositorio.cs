using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IProcedimientosRepositorio
{
    Task<RespuestaDto<ProcedimientosPaginadoDto>> ObtenerProcedimientosAsync(
        string? busqueda, int? anio, string? estado, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<ProcedimientoDetalleDto>> ObtenerProcedimientoPorIdAsync(
        long idProcedimiento, CancellationToken ct);

    Task<RespuestaDto<List<OpcionCatalogoDto>>> ObtenerOpcionesAsync(CancellationToken ct);

    Task<RespuestaDto<long>> GuardarProcedimientoAsync(
        GuardarProcedimientoDto dto, long idUsuario, string? pcRegistro, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoProcedimientoAsync(
        long idProcedimiento, string estado, long idUsuario, CancellationToken ct);
}
