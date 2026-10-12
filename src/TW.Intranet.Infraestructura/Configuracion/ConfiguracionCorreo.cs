namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// Servicio de correo por API HTTPS (Railway bloquea SMTP fuera del plan Pro).
/// Variables: Correo__Proveedor (brevo), Correo__ApiKey, Correo__Remitente,
/// Correo__NombreRemitente, Correo__UrlBase (https://api.brevo.com/), Correo__TimeoutSegundos.
/// Sin ApiKey el sistema funciona igual: los envíos se registran como error "no configurado".
/// </summary>
public record ConfiguracionCorreo(
    string Proveedor,
    string ApiKey,
    string Remitente,
    string NombreRemitente,
    string UrlBase,
    int    TimeoutSegundos)
{
    public bool Configurado =>
        !string.IsNullOrWhiteSpace(ApiKey) && !string.IsNullOrWhiteSpace(Remitente);
}
