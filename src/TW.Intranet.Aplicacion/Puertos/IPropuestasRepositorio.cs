using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IPropuestasRepositorio
{
    Task<RespuestaDto<DatosNuevaPropuestaDto>> ObtenerDatosNuevaPropuestaAsync(
        long idRequerimiento, CancellationToken ct);

    Task<RespuestaDto<PropuestasPaginadoDto>> ObtenerPropuestasAsync(
        long? idRequerimiento, string? estado, string? busqueda, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<PropuestaDetalleDto>> ObtenerPropuestaPorIdAsync(
        long idPropuesta, CancellationToken ct);

    Task<RespuestaDto<GuardarPropuestaResultadoDto>> GuardarPropuestaAsync(
        GuardarPropuestaDto dto, long idUsuario, CancellationToken ct);
}
