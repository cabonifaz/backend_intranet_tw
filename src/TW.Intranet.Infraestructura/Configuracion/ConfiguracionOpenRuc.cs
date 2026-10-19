namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// OpenRUC (https://openruc.com): API gratuita, sin API key, solo personas jurídicas (RUC 20).
/// Variables: ConsultaRuc__OpenRuc__Habilitado, ConsultaRuc__OpenRuc__UrlBase, ConsultaRuc__OpenRuc__TimeoutSegundos.
/// </summary>
public record ConfiguracionOpenRuc(bool Habilitado, string UrlBase, int TimeoutSegundos);
