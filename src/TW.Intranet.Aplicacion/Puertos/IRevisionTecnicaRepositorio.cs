using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Revisión Técnica (HU-56 a HU-59) y Precotizaciones Técnicas del CRM (HU-60).</summary>
public interface IRevisionTecnicaRepositorio
{
    // Servicio Técnico › Revisión de Informes
    Task<RespuestaDto<BandejaInformesDto>> ObtenerBandejaAsync(FiltrosBandejaInformesDto filtros, bool exportar, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DetalleInformeTecnicoDto>> ObtenerDetalleAsync(long idInforme, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<InformeGuardadoDto>> GuardarInformeAsync(long idInforme, GuardarInformeTecnicoDto datos, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PrecotizacionGuardadaDto>> GuardarPrecotizacionAsync(long idInforme, GuardarPrecotizacionInformeDto datos, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PreparacionRevisionInformeDto>> PrepararRevisionAsync(long idInforme, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<InformeRevisadoDto>> RegistrarRevisionAsync(long idInforme, string? nota, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<HistorialInformeDto>> ObtenerHistorialAsync(long idInforme, string? categoria, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ArchivoEvidenciaMovilDto>> ObtenerArchivoFotoAsync(long idInforme, long idEvidencia, long idUsuario, CancellationToken ct);

    // CRM › Precotizaciones Técnicas
    Task<RespuestaDto<BandejaPrecotizacionesDto>> ObtenerBandejaPrecotizacionesAsync(FiltrosPrecotizacionesDto filtros, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DetallePrecotizacionDto>> ObtenerDetallePrecotizacionAsync(long idPrecotizacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PrecargaPrecotizacionDto>> ObtenerPrecargaPrecotizacionAsync(long idPrecotizacion, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<PrecotizacionConvertidaDto>> ConvertirPrecotizacionAsync(long idPrecotizacion, long idPropuesta, long idUsuario, CancellationToken ct);
}
