namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// Decolecta (https://decolecta.com, antes apis.net.pe): consulta de RUC con token (plan gratuito al registrarse).
/// Cubre RUC 10 (personas naturales con negocio) y sirve de respaldo de OpenRUC para RUC 20.
/// Variables: ConsultaRuc__Decolecta__Token (sin token no se usa), ConsultaRuc__Decolecta__Habilitado,
/// ConsultaRuc__Decolecta__UrlBase, ConsultaRuc__Decolecta__TimeoutSegundos.
/// </summary>
public record ConfiguracionDecolecta(bool Habilitado, string UrlBase, string Token, int TimeoutSegundos);
