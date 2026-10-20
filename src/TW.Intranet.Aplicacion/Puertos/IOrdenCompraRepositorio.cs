using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Órdenes de compra recibidas del cliente (Sprint 4, HU-22 a HU-28).</summary>
public interface IOrdenCompraRepositorio
{
    // Bandeja, detalle, modal de validación y timeline
    Task<RespuestaDto<BandejaOrdenesCompraDto>> ObtenerBandejaAsync(FiltrosBandejaOrdenesCompraDto filtros, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DetalleOrdenCompraDto>> ObtenerDetalleAsync(long idOc, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ValidacionOrdenCompraDto>> ObtenerValidacionAsync(long idOc, long? idPropuesta, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TimelineOrdenCompraDto>> ObtenerTimelineAsync(long idOc, bool registrarExportacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<RutaPdfOrdenCompraDto>> ObtenerRutaPdfAsync(long idOc, long idUsuario, CancellationToken ct);

    // Ficha de registro y edición
    Task<RespuestaDto<PreparacionOrdenCompraDto>> PrepararAsync(long idPropuesta, long? idOcReemplaza, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionEdicionOrdenCompraDto>> PrepararEdicionAsync(long idOc, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<List<PropuestaDisponibleOcDto>>> ObtenerPropuestasDisponiblesAsync(long? idCliente, long? idOc, string? busqueda, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DatosIaOrdenCompraDto>> ObtenerDatosIaAsync(IReadOnlyList<long> idsPropuesta, long idUsuario, CancellationToken ct);

    // Validación y guardado
    Task<RespuestaDto<ComparacionOrdenCompraDto>> CompararAsync(CompararOrdenCompraSolicitudDto solicitud,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> RegistrarAsync(long idPropuesta, RegistrarOrdenCompraSolicitudDto solicitud,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, ArchivoPdfOcDto pdf, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> EditarAsync(long idOc, EditarOrdenCompraSolicitudDto solicitud,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, ArchivoPdfOcDto? pdf, long idUsuario, CancellationToken ct);
    /// <summary>pdf null = solo valida (antes de guardar el archivo).</summary>
    Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> ReemplazarDocumentoAsync(long idOc, string? tipo, string? motivo,
        DatosOrdenCompraDto? datos, IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, ArchivoPdfOcDto? pdf,
        long idUsuario, CancellationToken ct);
    Task<RespuestaDto<List<RevalidacionOrdenCompraDto>>> RevalidarAsync(long idOc, long? idPropuesta,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<object>> VincularNuevaVersionAsync(long idOc, long idPropuesta, long idPropuestaNueva, long idUsuario, CancellationToken ct);

    // OC autogenerada y anulación
    Task<RespuestaDto<OcAutogeneradaDto>> AutogenerarAsync(long idPropuesta, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionAnulacionOcDto>> PrepararAnulacionAsync(long idOc, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<AnulacionOrdenCompraDto>> AnularAsync(long idOc, AnularOrdenCompraSolicitudDto solicitud, long idUsuario, CancellationToken ct);
}
