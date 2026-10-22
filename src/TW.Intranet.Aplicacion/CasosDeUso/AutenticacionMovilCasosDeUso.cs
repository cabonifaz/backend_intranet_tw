using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-01 — Acceso seguro a la app de campo ───────────────────────

/// <summary>
/// Ingreso a la app con usuario (asignado por el jefe) y contraseña. No acepta correo.
/// 1 usuario = 1 equipo a la vez: si hay una sesión vigente en otro equipo se rechaza
/// (o se reemplaza, según OpcionesSesionMovil). La sesión de la intranet no se toca.
/// </summary>
public class IniciarSesionMovilCasoDeUso(
    IAutenticacionMovilRepositorio repositorio,
    IJwtServicio                   jwtServicio,
    IVerificadorContrasena         verificador,
    IControlIntentosIngreso        intentos,
    OpcionesSesionMovil            opciones)
{
    public const string MensajeCredenciales = "Usuario o contraseña incorrectos.";

    // Límites de entrada (desarrollo seguro): iguales o menores que las columnas de la BD.
    private const int MaxUsuario           = 50;   // usuario.nombre_usuario
    private const int MaxContrasena        = 128;
    private const int MaxIdDispositivo     = 100;  // sesion_usuario.id_dispositivo
    private const int MaxNombreDispositivo = 150;  // sesion_usuario.nombre_dispositivo

    // Hash bcrypt (costo 12, como los de la BD) de un texto que no es contraseña de nadie.
    // Si el usuario no existe se verifica contra este hash, para que la respuesta tarde lo mismo
    // y no se pueda adivinar qué usuarios existen midiendo el tiempo.
    private const string HashFicticio = "$2a$12$lBVL4EMoXo6XQXXtzAuL8OslwT83z09ZHcen6oy.GirMgVhbWSh6a";

    public async Task<RespuestaDto<IniciarSesionMovilSalidaDto>> EjecutarAsync(
        IniciarSesionMovilEntradaDto entrada, string? ipOrigen, CancellationToken ct = default)
    {
        var nombreUsuario = (entrada.Usuario ?? string.Empty).Trim().ToLowerInvariant();
        var contrasena    = entrada.Contrasena ?? string.Empty;
        var idDispositivo = (entrada.IdDispositivo ?? string.Empty).Trim();

        if (nombreUsuario.Length == 0 || contrasena.Length == 0)
            return new(1, "Ingresa tu usuario y contraseña.");

        // La app solo acepta el usuario asignado por el jefe, nunca el correo.
        if (nombreUsuario.Contains('@'))
            return new(1, "Ingresa con tu usuario, no con tu correo. Si no lo tienes, pídeselo a tu jefe.");

        // Un texto más largo que la columna nunca es un usuario válido.
        if (nombreUsuario.Length > MaxUsuario || contrasena.Length > MaxContrasena)
            return new(1, MensajeCredenciales);

        if (idDispositivo.Length == 0 || idDispositivo.Length > MaxIdDispositivo)
            return new(1, "No se pudo identificar el equipo. Vuelve a intentarlo.");

        var nombreDispositivo = entrada.NombreDispositivo?.Trim();
        if (nombreDispositivo is { Length: > MaxNombreDispositivo }) nombreDispositivo = nombreDispositivo[..MaxNombreDispositivo];

        // Fuerza bruta: el usuario escrito (exista o no) queda bloqueado tras varios fallos.
        if (intentos.TiempoBloqueoRestante(nombreUsuario) is { } restante)
            return new(1, $"Demasiados intentos fallidos. Vuelve a intentarlo en {Math.Max(1, (int)Math.Ceiling(restante.TotalMinutes))} min " +
                          "o pide a tu jefe que restablezca tu contraseña.");

        var respuestaUsuario = await repositorio.ObtenerPorNombreUsuarioAsync(nombreUsuario, ct);
        if (respuestaUsuario.IdTipoMensaje == 3)
            return new(3, respuestaUsuario.Mensaje);

        var usuario = respuestaUsuario.IdTipoMensaje == 2 ? respuestaUsuario.Datos : null;

        // Siempre se verifica un hash (el real o el ficticio): mismo tiempo de respuesta y mismo mensaje.
        var contrasenaValida = verificador.Verificar(contrasena, usuario?.PasswordHash ?? HashFicticio);
        if (usuario is null || !contrasenaValida)
        {
            intentos.RegistrarFallo(nombreUsuario);
            return new(1, MensajeCredenciales);
        }

        intentos.Reiniciar(nombreUsuario);

        if (usuario.Estado != "activo")
            return new(1, "Tu cuenta no está activa. Comunícate con tu jefe.");

        if (usuario.CanalAcceso != "movil" && usuario.CanalAcceso != "todos")
            return new(1, "Tu usuario no tiene acceso a la app de campo. Comunícate con tu jefe.");

        var horas = opciones.HorasExpiracion > 0 ? opciones.HorasExpiracion : 12;

        var sesion = await repositorio.IniciarSesionAsync(
            usuario.IdUsuario,
            idDispositivo,
            nombreDispositivo,
            ipOrigen,
            horas,
            opciones.ReemplazarSesionAnterior,
            ct);

        if (sesion.IdTipoMensaje != 2 || sesion.Datos is null)
            return new(sesion.IdTipoMensaje, sesion.Mensaje);

        var expiraUtc = DateTime.UtcNow.AddHours(horas);
        var token     = jwtServicio.GenerarTokenMovil(usuario, sesion.Datos.SesionToken, expiraUtc);

        var salida = new IniciarSesionMovilSalidaDto(
            token,
            expiraUtc,
            usuario.IdUsuario,
            usuario.NombreUsuario,
            usuario.Nombre,
            usuario.Apellido,
            usuario.Cargo,
            usuario.Area,
            usuario.RolSistema,
            usuario.ForzarCambioContrasena);

        return new(2, "Sesión iniciada exitosamente.", salida);
    }
}

/// <summary>Cierra la sesión de la app del equipo actual (queda libre para otro equipo).</summary>
public class CerrarSesionMovilCasoDeUso(IAutenticacionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, string sesionToken, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || string.IsNullOrWhiteSpace(sesionToken))
            return Task.FromResult(new RespuestaDto<bool>(1, "No se pudo identificar la sesión."));

        return repositorio.CerrarSesionAsync(idUsuario, sesionToken, ct);
    }
}

/// <summary>El jefe cierra la sesión de la app de un usuario (equipo perdido, cambio de celular).</summary>
public class LiberarSesionMovilCasoDeUso(IAutenticacionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, long idEjecutor, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "Usuario no válido."));

        return repositorio.LiberarSesionAsync(idUsuario, idEjecutor, ct);
    }
}

/// <summary>
/// El jefe asigna el usuario con el que la persona entra a la app (o se lo quita).
/// Formato: 4 a 30 caracteres, solo minúsculas, números, punto, guion o guion bajo.
/// </summary>
public partial class AsignarAccesoMovilCasoDeUso(IAutenticacionMovilRepositorio repositorio)
{
    [GeneratedRegex("^[a-z0-9._-]{4,30}$")]
    private static partial Regex FormatoUsuario();

    public Task<RespuestaDto<bool>> EjecutarAsync(
        long idUsuario, AsignarAccesoMovilDto dto, long idEjecutor, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "Usuario no válido."));

        string? nombreUsuario = null;
        if (dto.Habilitar)
        {
            nombreUsuario = (dto.NombreUsuario ?? string.Empty).Trim().ToLowerInvariant();
            if (!FormatoUsuario().IsMatch(nombreUsuario))
                return Task.FromResult(new RespuestaDto<bool>(1,
                    "El usuario debe tener de 4 a 30 caracteres: letras minúsculas, números, punto, guion o guion bajo (sin espacios ni @)."));
        }

        return repositorio.AsignarAccesoAsync(idUsuario, nombreUsuario, dto.Habilitar, idEjecutor, ct);
    }
}

/// <summary>Estado del acceso a la app de un usuario: usuario asignado y sesión vigente.</summary>
public class ObtenerAccesoMovilCasoDeUso(IAutenticacionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<AccesoMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<AccesoMovilDto>(1, "Usuario no válido."));

        return repositorio.ObtenerAccesoAsync(idUsuario, ct);
    }
}
