using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Alertas y apoyo en campo de la app móvil del jefe (App Mobile HU-32).</summary>
public interface IAlertasCampoMovilRepositorio
{
    Task<RespuestaDto<AlertaCampoMovilDto>> ObtenerAlertaAsync(long idUsuario, long idNotificacion, CancellationToken ct);

    Task<RespuestaDto<ContactoAlertaMovilDto>> AccionAsync(long idUsuario, long idNotificacion, string accion, string? mensaje, CancellationToken ct);

    Task<RespuestaDto<ReasignacionOsMovilDto>> ObtenerTecnicosAsync(long idUsuario, long idOs, CancellationToken ct);

    Task<RespuestaDto<ReasignadoMovilDto>> ReasignarAsync(long idUsuario, long idOs, long idTecnico, CancellationToken ct);

    Task<RespuestaDto<IncidenciaRegistradaMovilDto>> RegistrarIncidenciaAsync(
        long idUsuario, long idOs, int idTipo, int idNivel, string impacto, string descripcion, string? rutaFoto, bool escalar, CancellationToken ct);
}
