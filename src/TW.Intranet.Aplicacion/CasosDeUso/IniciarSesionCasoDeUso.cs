using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class IniciarSesionCasoDeUso(
    IAutenticacionRepositorio repositorio,
    IJwtServicio              jwtServicio,
    IVerificadorContrasena    verificador)
{
    public async Task<RespuestaDto<IniciarSesionSalidaDto>> EjecutarAsync(
        IniciarSesionEntradaDto entrada,
        CancellationToken ct = default)
    {
        var respuestaUsuario = await repositorio.ObtenerPorCorreoAsync(entrada.Correo, ct);

        if (respuestaUsuario.IdTipoMensaje != 2)
            return new RespuestaDto<IniciarSesionSalidaDto>(
                respuestaUsuario.IdTipoMensaje,
                respuestaUsuario.Mensaje);

        var usuario = respuestaUsuario.Datos!;

        if (!verificador.Verificar(entrada.Contrasena, usuario.PasswordHash))
            return new RespuestaDto<IniciarSesionSalidaDto>(1, "Correo o contraseña incorrectos.");

        if (usuario.Estado != "activo")
            return new RespuestaDto<IniciarSesionSalidaDto>(
                1, "Tu cuenta no está activa. Contacta al administrador.");

        if (usuario.CanalAcceso != "intranet" && usuario.CanalAcceso != "todos")
            return new RespuestaDto<IniciarSesionSalidaDto>(
                1, "No tienes permiso para acceder a la intranet.");

        var loginResult = await repositorio.ActualizarUltimoLoginAsync(usuario.IdUsuario, ct);
        if (loginResult.IdTipoMensaje != 2)
            return new RespuestaDto<IniciarSesionSalidaDto>(loginResult.IdTipoMensaje, loginResult.Mensaje);

        var usuarioConToken = usuario with { SesionToken = loginResult.Datos! };

        var token = jwtServicio.GenerarToken(usuarioConToken);

        var salida = new IniciarSesionSalidaDto(
            token,
            usuarioConToken.Nombre,
            usuarioConToken.Apellido,
            usuarioConToken.Correo,
            usuarioConToken.RolSistema);

        return new RespuestaDto<IniciarSesionSalidaDto>(2, "Sesión iniciada exitosamente.", salida);
    }
}
