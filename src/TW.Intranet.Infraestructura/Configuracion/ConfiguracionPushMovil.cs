namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// Servicio de notificaciones push de Expo. <c>AccessToken</c> es opcional: solo hace falta si en expo.dev se activó la
/// "seguridad mejorada" de las notificaciones push (variable PushMovil__AccessToken).
/// </summary>
public record ConfiguracionPushMovil(string AccessToken = "");
