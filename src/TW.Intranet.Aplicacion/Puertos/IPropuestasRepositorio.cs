using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IPropuestasRepositorio
{
    Task<RespuestaDto<DatosNuevaPropuestaDto>> ObtenerDatosNuevaPropuestaAsync(
        long idRequerimiento, CancellationToken ct);

    Task<RespuestaDto<PropuestasPaginadoDto>> ObtenerPropuestasAsync(
        FiltrosPropuestasDto filtros, CancellationToken ct);

    Task<RespuestaDto<KpisPropuestasDto>> ObtenerKpisAsync(
        int? anio, long? idComercial, CancellationToken ct);

    Task<RespuestaDto<PropuestaDetalleDto>> ObtenerPropuestaPorIdAsync(
        long idPropuesta, CancellationToken ct);

    Task<RespuestaDto<GuardarPropuestaResultadoDto>> GuardarPropuestaAsync(
        GuardarPropuestaDto dto, long idUsuario, CancellationToken ct);
}
