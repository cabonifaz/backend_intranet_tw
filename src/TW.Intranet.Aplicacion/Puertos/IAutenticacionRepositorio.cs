using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Dominio.Entidades;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IAutenticacionRepositorio
{
    Task<RespuestaDto<Usuario>> ObtenerPorCorreoAsync(string correo, CancellationToken ct);
    Task<RespuestaDto<string>> ActualizarUltimoLoginAsync(long idUsuario, CancellationToken ct);
    Task<bool> VerificarSesionTokenAsync(long idUsuario, string sesionToken, CancellationToken ct);
}
