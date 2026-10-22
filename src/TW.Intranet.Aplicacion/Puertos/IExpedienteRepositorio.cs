using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Expediente Digital (Sprint 4, HU-29 a HU-33). Solo lectura, salvo la reasignación de responsables (HU-33).</summary>
public interface IExpedienteRepositorio
{
    // HU-29
    /// <summary>exportar = true: todas las filas filtradas, sin paginar (Exportar XLSX).</summary>
    Task<RespuestaDto<BandejaExpedientesDto>> ObtenerBandejaAsync(FiltrosBandejaExpedientesDto filtros, bool exportar, long idUsuario, CancellationToken ct);

    // HU-30
    Task<RespuestaDto<DetalleExpedienteDto>> ObtenerDetalleAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabRqExpedienteDto>> ObtenerTabRqAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabPropuestasExpedienteDto>> ObtenerTabPropuestasAsync(long idExpediente, long? idPropuesta, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<object>> ValidarComparacionAsync(long idExpediente, long idBase, long idDestino, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabVistoBuenoExpedienteDto>> ObtenerTabVistoBuenoAsync(long idExpediente, string? numero, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabSeguimientoExpedienteDto>> ObtenerTabSeguimientoAsync(long idExpediente, string? numero, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabOrdenesCompraExpedienteDto>> ObtenerTabOrdenesCompraAsync(long idExpediente, long? idOc, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabOrdenServicioExpedienteDto>> ObtenerTabOrdenServicioAsync(long idExpediente, long? idOs, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabProgramacionExpedienteDto>> ObtenerTabProgramacionAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabSsomaExpedienteDto>> ObtenerTabSsomaAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabEjecucionExpedienteDto>> ObtenerTabEjecucionAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TabCierreExpedienteDto>> ObtenerTabCierreAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<IReadOnlyList<ArchivoExportacionExpedienteDto>>> ObtenerArchivosExportacionAsync(long idExpediente, long idUsuario, CancellationToken ct);

    // HU-31
    /// <summary>exportar = true registra la exportación de la lista (XLSX) en la auditoría.</summary>
    Task<RespuestaDto<DocumentosExpedienteDto>> ObtenerDocumentosAsync(long idExpediente, FiltrosDocumentosExpedienteDto filtros, bool exportar, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<UbicacionArchivoExpedienteDto>> ObtenerArchivoAsync(long idExpediente, string clave, long idUsuario, CancellationToken ct);

    // HU-32
    /// <summary>tabExportado (timeline, reasignaciones, bloqueos, alertas_sla) registra la exportación en la auditoría.</summary>
    Task<RespuestaDto<HistorialExpedienteDto>> ObtenerHistorialAsync(long idExpediente, FiltrosHistorialExpedienteDto filtros, string? tabExportado, long idUsuario, CancellationToken ct);

    // HU-33
    Task<RespuestaDto<PreparacionReasignacionExpedienteDto>> PrepararReasignacionAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<CarteraComercialExpedienteDto>> ObtenerCarteraComercialAsync(long idExpediente, long? idResponsable, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>> BuscarResponsablesAsync(string? busqueda, long? idExcluir, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ReasignacionExpedienteDto>> ReasignarResponsableAsync(long idExpediente, ReasignarResponsableExpedienteDto datos, long idUsuario, CancellationToken ct);
}
