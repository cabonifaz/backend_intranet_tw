namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-01 — Acceso a la app de campo ──────────────────────────────

/// <summary>
/// Configuración de la sesión de la app (sección AppMovil del appsettings / variables de Railway).
///   HorasExpiracion .......... duración de la sesión y del JWT de la app (por defecto 12 h).
///   ReemplazarSesionAnterior . false = si hay una sesión vigente en otro equipo se rechaza el ingreso;
///                              true  = el nuevo equipo cierra la sesión del anterior.
/// </summary>
public record OpcionesSesionMovil(int HorasExpiracion, bool ReemplazarSesionAnterior);

/// <summary>
/// Desarrollo seguro del ingreso a la app (sección AppMovil del appsettings / variables del servidor).
///   MaxIntentosFallidos ...... fallos seguidos de un mismo usuario antes de bloquearlo (por defecto 5).
///   MinutosBloqueo ........... minutos de bloqueo y ventana en que se cuentan los fallos (por defecto 15).
///   IngresosPorMinutoPorIp ... ingresos permitidos por minuto desde una misma IP (por defecto 10).
/// </summary>
public record OpcionesSeguridadMovil(int MaxIntentosFallidos, int MinutosBloqueo, int IngresosPorMinutoPorIp);

/// <summary>Ingreso a la app: solo con usuario (no correo) + contraseña + id del equipo.</summary>
public record IniciarSesionMovilEntradaDto(
    string  Usuario,
    string  Contrasena,
    string  IdDispositivo,
    string? NombreDispositivo);

public record IniciarSesionMovilSalidaDto(
    string   Token,
    DateTime ExpiraEn,
    long     IdUsuario,
    string   Usuario,
    string   Nombre,
    string   Apellido,
    string?  Cargo,
    string?  Area,
    string   RolSistema,
    bool     ForzarCambioContrasena);

/// <summary>Sesión abierta por SP_IniciarSesionMovil.</summary>
public record SesionMovilDto(string SesionToken, DateTime FechaExpiracion);

/// <summary>El jefe asigna (Habilitar = true) o quita (false) el usuario de la app.</summary>
public record AsignarAccesoMovilDto(string? NombreUsuario, bool Habilitar = true);

/// <summary>Estado del acceso a la app de un usuario (ficha de usuario de la intranet).</summary>
public record AccesoMovilDto(
    long      IdUsuario,
    string?   NombreUsuario,
    string    CanalAcceso,
    bool      Habilitado,
    string?   SesionEquipo,
    DateTime? SesionInicio,
    DateTime? SesionExpira);
