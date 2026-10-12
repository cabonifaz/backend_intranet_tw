namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Opciones del correo que usan los casos de uso (Correo:* en appsettings / variables).</summary>
public record OpcionesCorreo(string UrlIntranet, string NombreSistema);

/// <summary>
/// Mensaje listo para enviar. Html y Texto ya vienen armados desde la plantilla.
/// Opcionales (HU-19): más destinatarios, copias, responder-a y nombre visible del remitente.
/// </summary>
public record MensajeCorreoDto(
    string  Para,
    string? NombrePara,
    string  Asunto,
    string  Html,
    string  Texto,
    IReadOnlyList<DestinatarioCorreoDto>? ParaAdicionales = null,
    IReadOnlyList<DestinatarioCorreoDto>? Cc              = null,
    string? ResponderA       = null,
    string? NombreResponderA = null,
    string? NombreRemitente  = null);

/// <summary>Destinatario adicional o en copia.</summary>
public record DestinatarioCorreoDto(string Correo, string? Nombre);

/// <summary>Resultado de un envío. El adaptador nunca lanza: los errores vienen aquí.</summary>
public record ResultadoEnvioCorreoDto(
    bool    Enviado,
    string  Proveedor,
    string? IdMensaje,
    string? Error);

/// <summary>Respuesta de POST api/maestros/usuarios (crear / editar).</summary>
public record UsuarioGuardadoDto(
    long    IdUsuario,
    bool    CorreoSolicitado,     // el admin marcó "enviar credenciales"
    bool    CorreoEnviado,
    string? CorreoDestino,
    string? CorreoError);

/// <summary>Respuesta de POST api/maestros/usuarios/{id}/reenviar-credenciales.</summary>
public record ReenvioCredencialesDto(
    long    IdUsuario,
    string  Correo,
    bool    CorreoEnviado,
    string? CorreoError,
    // Solo viene si el correo NO salió, para que el admin la entregue a mano
    // (la contraseña anterior ya no sirve). Nunca se guarda en texto plano.
    string? ContrasenaTemporal);

/// <summary>Datos del usuario tras restablecer su contraseña temporal.</summary>
public record DatosCredencialUsuarioDto(long IdUsuario, string Correo, string Nombre, string Apellido);

/// <summary>Body de POST api/admin/correo/prueba.</summary>
public class EnviarCorreoPruebaDto
{
    public string? Para { get; set; }
}

public record ResultadoCorreoPruebaDto(string Para, string Proveedor, string? IdMensaje);
