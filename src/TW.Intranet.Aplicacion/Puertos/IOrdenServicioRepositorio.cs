using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Módulo Órdenes de Servicio / Metrología (OS / OM), HU-40 a HU-44.</summary>
public interface IOrdenServicioRepositorio
{
    /// <summary>HU-41 Bandeja. exportar = true: todas las filas, sin paginar.</summary>
    Task<RespuestaDto<BandejaOrdenesServicioDto>> ObtenerBandejaAsync(
        FiltrosBandejaOrdenesServicioDto filtros, bool exportar, long idUsuario, CancellationToken ct);

    // ── HU-40 ──
    /// <summary>Ficha nueva (idPropuesta) o de edición (idOs).</summary>
    Task<RespuestaDto<FichaOrdenServicioDto>> PrepararAsync(long? idPropuesta, long? idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<OrdenServicioGuardadaDto>> GuardarAsync(long idOs, GuardarOrdenServicioDto datos, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionSolicitudEdicionOsDto>> PrepararSolicitudEdicionAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<SolicitudEdicionOsDto>> SolicitarEdicionAsync(long idOs, int idMotivo, string comentario, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<SolicitudEdicionOsDto>> ResolverSolicitudEdicionAsync(long idSolicitud, bool aprobar, string? comentario, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionAnulacionOsDto>> PrepararAnulacionAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<AnulacionOrdenServicioDto>> AnularAsync(long idOs, int idMotivo, string comentario, long idUsuario, CancellationToken ct);

    // ── HU-42 ──
    Task<RespuestaDto<DetalleOrdenServicioDto>> ObtenerDetalleAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PropuestaOrigenOsDto>> ObtenerPropuestaOrigenAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<List<EquipoOrdenServicioDto>>> ObtenerEquiposAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<List<ConceptoOrdenServicioDto>>> ObtenerConceptosAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<string?>> ObtenerObservacionesAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ProgramacionOrdenServicioDto>> ObtenerProgramacionAsync(long idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<CertificadoOsDto>> ObtenerCertificadoAsync(long idOs, long idUsuario, CancellationToken ct);

    // ── HU-43 ──
    Task<RespuestaDto<BusquedaEquiposOsDto>> BuscarEquiposAsync(FiltrosBuscarEquiposOsDto filtros, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<BusquedaConceptosOsDto>> BuscarConceptosAsync(FiltrosBuscarConceptosOsDto filtros, long idUsuario, CancellationToken ct);

    // ── HU-44 ──
    Task<RespuestaDto<CandidatosImportacionOsDto>> ObtenerCandidatosImportacionAsync(
        long idCliente, long? idOs, IReadOnlyList<string> codigosTw, long idUsuario, CancellationToken ct);
}
