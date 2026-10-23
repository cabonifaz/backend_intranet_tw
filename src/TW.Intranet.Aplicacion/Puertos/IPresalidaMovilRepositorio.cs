using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Detalle del servicio y checklist de pre-salida de la app móvil (App Mobile HU-04).</summary>
public interface IPresalidaMovilRepositorio
{
    Task<RespuestaDto<DetalleServicioMovilDto>>  ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<HechosChecklistSalidaDto>> ObtenerHechosChecklistAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<bool>>                     MarcarItemAsync(long idUsuario, long idOs, string codigo, bool confirmado, CancellationToken ct);
    Task<RespuestaDto<bool>>                     SolicitarAutorizacionAsync(long idUsuario, long idOs, string? motivo, string pendientes, CancellationToken ct);
    Task<RespuestaDto<bool>>                     IniciarTrasladoAsync(long idUsuario, long idOs, bool conVistoBueno, CancellationToken ct);
}

/// <summary>Visto bueno de salida desde la intranet (encargado del área según la RQ).</summary>
public interface IAutorizacionSalidaRepositorio
{
    Task<RespuestaDto<List<AutorizacionSalidaBandejaDto>>> ObtenerAsync(long idUsuario, string? estado, CancellationToken ct);
    Task<RespuestaDto<bool>> ResolverAsync(long idJefe, long idOs, bool aprobar, string? comentario, CancellationToken ct);
}
