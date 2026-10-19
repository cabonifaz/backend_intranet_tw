using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Registro de envíos (correo_envio) y restablecimiento de contraseña temporal.</summary>
public class CorreoRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ICorreoRepositorio
{
    public Task<RespuestaDto<object>> RegistrarEnvioAsync(
        string tipo, MensajeCorreoDto mensaje, string? entidadTipo, long? idEntidad,
        ResultadoEnvioCorreoDto resultado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarCorreoEnvio",
            p =>
            {
                p.AddWithValue("p_tipo",         tipo);
                p.AddWithValue("p_destinatario", mensaje.Para);
                p.AddWithValue("p_asunto",       mensaje.Asunto);
                p.AddWithValue("p_entidad_tipo", Valor(entidadTipo));
                p.AddWithValue("p_id_entidad",   Valor(idEntidad));
                p.AddWithValue("p_proveedor",    resultado.Proveedor);
                p.AddWithValue("p_estado",       resultado.Enviado ? "enviado" : "error");
                p.AddWithValue("p_id_mensaje",   Valor(resultado.IdMensaje));
                p.AddWithValue("p_error",        Valor(resultado.Error));
                p.AddWithValue("p_id_usuario",   idUsuario);
            },
            (_, mensajeSp) => Task.FromResult(new RespuestaDto<object>(2, mensajeSp)), ct);

    public Task<RespuestaDto<DatosCredencialUsuarioDto>> RestablecerContrasenaTemporalAsync(
        long idUsuario, string passwordHash, long idEjecutor, CancellationToken ct)
        => EjecutarAsync("SP_RestablecerContrasenaTemporal",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_password_hash", passwordHash);
                p.AddWithValue("p_id_ejecutor",   idEjecutor);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DatosCredencialUsuarioDto>(3, "No se pudo leer el usuario.");
                return new RespuestaDto<DatosCredencialUsuarioDto>(2, mensaje, new DatosCredencialUsuarioDto(
                    EnteroLargo(r, "id_usuario"),
                    Texto(r, "correo") ?? "",
                    Texto(r, "nombre") ?? "",
                    Texto(r, "apellido") ?? ""));
            }, ct);
}
