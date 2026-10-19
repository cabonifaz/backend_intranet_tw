using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Expediente Digital (HU-29 a HU-34).</summary>
public interface IExpedienteRepositorio
{
    Task<RespuestaDto<BandejaExpedientesDto>> ObtenerBandejaAsync(FiltrosBandejaExpedientesDto filtros, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DetalleExpedienteDto>> ObtenerDetalleAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<WorkflowExpedienteDto>> ObtenerWorkflowAsync(long idExpediente, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<DocumentosExpedienteDto>> ObtenerDocumentosAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<UbicacionArchivoExpedienteDto>> ObtenerArchivoAsync(long idExpediente, string clave, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<IReadOnlyList<ArchivoExportacionExpedienteDto>>> ObtenerArchivosExportacionAsync(long idExpediente, long idUsuario, CancellationToken ct);

    /// <summary>ruta null + soloValidar = true valida antes de escribir el archivo.</summary>
    Task<RespuestaDto<DocumentoAdjuntadoDto>> AdjuntarDocumentoAsync(
        long idExpediente, AdjuntarDocumentoExpedienteDto datos, string? ruta, string? nombreArchivo, long? tamano,
        string? tipoContenido, string? hash, bool soloValidar, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<BloqueoRegistradoDto>> RegistrarBloqueoAsync(long idExpediente, RegistrarBloqueoExpedienteDto datos, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionResolucionBloqueoDto>> PrepararResolucionBloqueoAsync(long idExpediente, long idBloqueador, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<BloqueoResueltoDto>> ResolverBloqueoAsync(
        long idExpediente, long idBloqueador, ResolverBloqueoExpedienteDto datos, string? ruta, string? nombreArchivo, long? tamano,
        string? tipoContenido, string? hash, bool soloValidar, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<HistorialExpedienteDto>> ObtenerHistorialAsync(long idExpediente, FiltrosHistorialExpedienteDto filtros, bool exportar, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionReasignacionExpedienteDto>> PrepararReasignacionAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>> BuscarResponsablesAsync(long idExpediente, string? busqueda, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ReasignacionExpedienteDto>> ReasignarResponsableAsync(long idExpediente, ReasignarResponsableExpedienteDto datos, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<PreparacionAvanceExpedienteDto>> PrepararAvanceAsync(long idExpediente, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<AvanceExpedienteDto>> AvanzarEtapaAsync(long idExpediente, string? comentario, long idUsuario, CancellationToken ct);
}
