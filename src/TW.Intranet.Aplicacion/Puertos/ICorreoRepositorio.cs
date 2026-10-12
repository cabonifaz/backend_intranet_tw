using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Registro de correos enviados y restablecimiento de contraseña temporal.</summary>
public interface ICorreoRepositorio
{
    Task<RespuestaDto<object>> RegistrarEnvioAsync(
        string tipo, MensajeCorreoDto mensaje, string? entidadTipo, long? idEntidad,
        ResultadoEnvioCorreoDto resultado, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<DatosCredencialUsuarioDto>> RestablecerContrasenaTemporalAsync(
        long idUsuario, string passwordHash, long idEjecutor, CancellationToken ct);
}
