namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// IA de órdenes de compra con Google Gemini (API REST, nivel gratuito de Google AI Studio).
/// Variables: Gemini__ApiKey, Gemini__Modelo (gemini-3.5-flash-lite),
/// Gemini__UrlBase (https://generativelanguage.googleapis.com/), Gemini__TimeoutSegundos (60).
/// Asistente IA de la app móvil (HU-19): Gemini__ModeloAsistente (opcional; vacío = Gemini__Modelo). El asistente lee PDF, así que su cliente espera mínimo 90 s.
/// Sin ApiKey el módulo funciona igual: la ficha se llena a mano y la validación usa solo las reglas.
/// </summary>
public record ConfiguracionGemini(
    string ApiKey,
    string Modelo,
    string UrlBase,
    int    TimeoutSegundos)
{
    public bool Configurado => !string.IsNullOrWhiteSpace(ApiKey);
}
