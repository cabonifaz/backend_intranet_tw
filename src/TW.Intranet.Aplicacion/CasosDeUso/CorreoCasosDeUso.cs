using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Envía un correo y deja el registro en correo_envio.
/// El registro nunca impide el envío: si falla, el resultado del envío se devuelve igual.
/// </summary>
public class NotificadorCorreo(IEnviadorCorreo enviador, ICorreoRepositorio repositorio)
{
    public async Task<ResultadoEnvioCorreoDto> EnviarAsync(
        string tipo, MensajeCorreoDto mensaje, string? entidadTipo, long? idEntidad,
        long idUsuario, CancellationToken ct)
    {
        var resultado = await enviador.EnviarAsync(mensaje, ct);
        await repositorio.RegistrarEnvioAsync(tipo, mensaje, entidadTipo, idEntidad, resultado, idUsuario, ct);
        return resultado;
    }
}

/// <summary>
/// Genera una nueva contraseña temporal, la guarda (solo el hash, con cambio obligatorio)
/// y la envía por correo. Si el correo falla, devuelve la contraseña para entregarla a mano.
/// </summary>
public class ReenviarCredencialesCasoDeUso(
    ICorreoRepositorio  repositorio,
    IHasherContrasena   hasher,
    NotificadorCorreo   notificador,
    OpcionesCorreo      opciones)
{
    public async Task<RespuestaDto<ReenvioCredencialesDto>> EjecutarAsync(
        long idUsuario, long idEjecutor, CancellationToken ct)
    {
        if (idUsuario <= 0) return new(1, "Usuario no válido.");

        string contrasena = GeneradorContrasenaTemporal.Generar();
        var restablecido = await repositorio.RestablecerContrasenaTemporalAsync(
            idUsuario, hasher.Hash(contrasena), idEjecutor, ct);
        if (restablecido.IdTipoMensaje != 2 || restablecido.Datos is null)
            return new(restablecido.IdTipoMensaje, restablecido.Mensaje);

        var u = restablecido.Datos;
        var mensaje = PlantillasCorreo.Credenciales(u.Correo, $"{u.Nombre} {u.Apellido}".Trim(), contrasena, opciones, esReenvio: true);
        var envio = await notificador.EnviarAsync("reenvio_credenciales", mensaje, "usuario", u.IdUsuario, idEjecutor, ct);

        return envio.Enviado
            ? new(2, $"Se envió una nueva contraseña temporal a {u.Correo}.",
                  new ReenvioCredencialesDto(u.IdUsuario, u.Correo, true, null, null))
            : new(2, $"Se generó una nueva contraseña temporal, pero no se pudo enviar el correo ({envio.Error}). Entréguela al usuario por otro medio.",
                  new ReenvioCredencialesDto(u.IdUsuario, u.Correo, false, envio.Error, contrasena));
    }
}

/// <summary>Correo de prueba para validar la configuración del servicio (solo administradores).</summary>
public class EnviarCorreoPruebaCasoDeUso(NotificadorCorreo notificador, OpcionesCorreo opciones)
{
    public async Task<RespuestaDto<ResultadoCorreoPruebaDto>> EjecutarAsync(
        EnviarCorreoPruebaDto dto, long idEjecutor, CancellationToken ct)
    {
        string para = (dto.Para ?? "").Trim();
        if (para.Length < 5 || !para.Contains('@') || para.Contains(' '))
            return new(1, "Ingrese un correo de destino válido.");

        var envio = await notificador.EnviarAsync("prueba", PlantillasCorreo.Prueba(para, opciones, DateTime.Now),
                                                 null, null, idEjecutor, ct);
        return envio.Enviado
            ? new(2, $"Correo de prueba enviado a {para}.", new ResultadoCorreoPruebaDto(para, envio.Proveedor, envio.IdMensaje))
            : new(1, $"No se pudo enviar el correo de prueba: {envio.Error}");
    }
}
