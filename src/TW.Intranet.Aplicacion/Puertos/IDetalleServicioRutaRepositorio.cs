using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-52 Detalle del Servicio en Ruta (Sprint 5). Solo lectura.</summary>
public interface IDetalleServicioRutaRepositorio
{
    Task<RespuestaDto<DetalleServicioRutaDto>>   ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<AvanceServicioRutaDto>>    ObtenerAvanceAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<SeccionEquipoRutaDto>>     ObtenerSeccionEquipoAsync(long idUsuario, long idOs, long idEquipo, string seccion, CancellationToken ct);
    Task<RespuestaDto<MapaServicioRutaDto>>      ObtenerMapaAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<TimelineServicioRutaDto>>  ObtenerTimelineAsync(long idUsuario, long idOs, ConsultaTimelineNormalizada q, CancellationToken ct);
    Task<RespuestaDto<IncidenciasServicioRutaDto>> ObtenerIncidenciasAsync(long idUsuario, long idOs, string? clave, CancellationToken ct);
    Task<RespuestaDto<CierreServicioRutaDto>>    ObtenerCierreAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<AuditoriaServicioRutaDto>> ObtenerAuditoriaAsync(long idUsuario, long idOs, CancellationToken ct);
}
