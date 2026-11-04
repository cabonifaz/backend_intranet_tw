using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-51 Bandeja de Seguimiento Operativo (Sprint 5). Solo lectura.</summary>
public interface ISeguimientoOperativoRepositorio
{
    Task<RespuestaDto<ResumenSeguimientoDto>>        ObtenerResumenAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<ServiciosSeguimientoDto>>      ObtenerServiciosAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<TecnicosSeguimientoDto>>       ObtenerTecnicosAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<IncidenciasSeguimientoDto>>    ObtenerIncidenciasAsync(ConsultaSeguimientoNormalizada q, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<OpcionesFiltrosSeguimientoDto>> ObtenerFiltrosAsync(long idUsuario, CancellationToken ct);
    /// <summary>App móvil: registra la posición GPS del técnico (única escritura del paquete; la bandeja sigue siendo de solo lectura).</summary>
    Task<RespuestaDto<UbicacionRegistradaDto>>       RegistrarUbicacionAsync(long idUsuario, long idOs, decimal latitud, decimal longitud, decimal? precisionMetros, CancellationToken ct);
}
