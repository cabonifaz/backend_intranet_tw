using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Dominio.Entidades;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Acceso y sesiones de la app móvil de campo (App Mobile HU-01).</summary>
public interface IAutenticacionMovilRepositorio
{
    Task<RespuestaDto<Usuario>>        ObtenerPorNombreUsuarioAsync(string nombreUsuario, CancellationToken ct);
    Task<RespuestaDto<SesionMovilDto>> IniciarSesionAsync(long idUsuario, string idDispositivo, string? nombreDispositivo,
                                                          string? ipOrigen, int horasExpiracion, bool reemplazarSesion,
                                                          CancellationToken ct);
    Task<bool>                         VerificarSesionAsync(long idUsuario, string sesionToken, CancellationToken ct);
    Task<RespuestaDto<bool>>           CerrarSesionAsync(long idUsuario, string sesionToken, CancellationToken ct);
    Task<RespuestaDto<bool>>           LiberarSesionAsync(long idUsuario, long idEjecutor, CancellationToken ct);
    Task<RespuestaDto<bool>>           AsignarAccesoAsync(long idUsuario, string? nombreUsuario, bool habilitar,
                                                          long idEjecutor, CancellationToken ct);
    Task<RespuestaDto<AccesoMovilDto>> ObtenerAccesoAsync(long idUsuario, CancellationToken ct);
}
