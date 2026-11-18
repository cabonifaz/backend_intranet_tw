namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile — Notificaciones push (bandeja de notificaciones del teléfono) ───────────────

/// <summary>
/// Lo que manda la app al iniciar sesión: el identificador de la instalación (el mismo con el que inicia sesión), el token de Expo Push
/// ("ExponentPushToken[...]") y la plataforma ("android").
/// </summary>
public record RegistrarDispositivoPushEntradaDto(string? IdDispositivo, string? Token, string? Plataforma);

/// <summary>Un teléfono con sesión de un usuario, al que se le puede enviar una notificación.</summary>
public record DispositivoPushDto(long IdUsuario, string Token);

/// <summary>Una notificación lista para la bandeja del teléfono. Prioridad: critica | alta | normal.</summary>
public record MensajePushDto(string Token, string Titulo, string Cuerpo, long IdNotificacion, string Prioridad);

/// <summary>Resultado de un envío: cuántos aceptó el servicio de push, los tokens que ya no sirven (app desinstalada) y el último error, si hubo.</summary>
public record ResultadoEnvioPushDto(int Enviados, List<string> TokensInvalidos, string? Error);
