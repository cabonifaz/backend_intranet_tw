using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Base de los adaptadores de Google Gemini (órdenes de compra, importación de equipos):
/// POST {UrlBase}v1beta/models/{modelo}:generateContent con header "x-goog-api-key",
/// respuesta estructurada (responseMimeType application/json + responseSchema) y temperatura 0.
/// El HttpClient llega con BaseAddress y Timeout desde Program.cs.
/// </summary>
public abstract class GeminiClienteBase(HttpClient http, ConfiguracionGemini configuracion)
{
    protected static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>Respuestas recientes (30 min) por hash de la consulta (compartido por todos los adaptadores).</summary>
    private static readonly ConcurrentDictionary<string, (string Texto, DateTime Vence)> Cache = new();

    public bool   Disponible => configuracion.Configurado;
    public string Motor      => configuracion.Modelo;

    // ══════════════════════ Llamada a Gemini ══════════════════════

    protected async Task<(string? Texto, string? Error)> GenerarAsync(string instruccion, JsonArray partes, JsonObject esquema, CancellationToken ct)
    {
        var configGeneracion = new JsonObject
        {
            ["temperature"]      = 0,
            ["responseMimeType"] = "application/json",
            ["responseSchema"]   = esquema,
        };
        // Solo la familia 2.5 acepta thinkingBudget = 0 (desactiva el razonamiento). Los modelos 3.x usan su
        // configuración por defecto: enviarles thinkingBudget puede devolver error.
        if (configuracion.Modelo.StartsWith("gemini-2.5", StringComparison.OrdinalIgnoreCase)
            && configuracion.Modelo.Contains("flash", StringComparison.OrdinalIgnoreCase))
            configGeneracion["thinkingConfig"] = new JsonObject { ["thinkingBudget"] = 0 };

        var cuerpo = new JsonObject
        {
            ["systemInstruction"] = new JsonObject { ["parts"] = new JsonArray { new JsonObject { ["text"] = instruccion } } },
            ["contents"]          = new JsonArray { new JsonObject { ["role"] = "user", ["parts"] = partes } },
            ["generationConfig"]  = configGeneracion,
        };

        // La misma consulta (validar en vivo y luego guardar) no se repite: ahorra cuota del nivel gratuito.
        var json  = cuerpo.ToJsonString();
        var clave = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(configuracion.Modelo + "|" + json)));
        if (Cache.TryGetValue(clave, out var guardado) && guardado.Vence > DateTime.UtcNow)
            return (guardado.Texto, null);

        try
        {
            using var solicitud = new HttpRequestMessage(HttpMethod.Post,
                $"v1beta/models/{Uri.EscapeDataString(configuracion.Modelo)}:generateContent")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json"),
            };
            solicitud.Headers.Add("x-goog-api-key", configuracion.ApiKey);

            using var respuesta = await http.SendAsync(solicitud, ct);
            var texto = await respuesta.Content.ReadAsStringAsync(ct);

            if (!respuesta.IsSuccessStatusCode)
                return (null, respuesta.StatusCode switch
                {
                    HttpStatusCode.NotFound => $"El modelo de IA \"{configuracion.Modelo}\" no está disponible en Gemini. Configure un modelo vigente en Gemini__Modelo (por ejemplo gemini-3.5-flash-lite).",
                    HttpStatusCode.TooManyRequests => "Se alcanzó el límite gratuito de la IA (Gemini). Intente en un minuto o continúe con la carga manual.",
                    HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden => "La API key de Gemini no es válida o no tiene permiso.",
                    HttpStatusCode.BadRequest when texto.Contains("API key", StringComparison.OrdinalIgnoreCase)
                        => "La API key de Gemini no es válida.",
                    _ => $"La IA no respondió correctamente (HTTP {(int)respuesta.StatusCode}).",
                });

            var raiz = JsonNode.Parse(texto);
            var candidato = raiz?["candidates"]?[0];
            var finRazon  = candidato?["finishReason"]?.GetValue<string>();
            var partesResp = candidato?["content"]?["parts"] as JsonArray;
            var salida = partesResp is null
                ? null
                : string.Concat(partesResp.Select(p => p?["text"]?.GetValue<string>() ?? ""));

            if (string.IsNullOrWhiteSpace(salida))
                return (null, finRazon is "SAFETY" or "RECITATION" or "PROHIBITED_CONTENT"
                    ? "La IA no pudo procesar el documento."
                    : "La IA no devolvió datos.");

            if (Cache.Count > 200)
                foreach (var vencido in Cache.Where(c => c.Value.Vence <= DateTime.UtcNow).Select(c => c.Key).ToList())
                    Cache.TryRemove(vencido, out _);
            if (Cache.Count <= 200)
                Cache[clave] = (salida, DateTime.UtcNow.AddMinutes(30));
            return (salida, null);
        }
        catch (TaskCanceledException) when (!ct.IsCancellationRequested)
        {
            return (null, "La IA tardó demasiado en responder. Continúe con la carga manual o intente de nuevo.");
        }
        catch (HttpRequestException)
        {
            return (null, "No se pudo conectar con la IA (Gemini).");
        }
        catch (JsonException)
        {
            return (null, "La IA devolvió una respuesta que no se pudo interpretar.");
        }
    }

    // ══════════════════════ Esquema y lectura ══════════════════════

    protected static JsonObject Tipo(string tipo, bool nulo)
    {
        var o = new JsonObject { ["type"] = tipo };
        if (nulo) o["nullable"] = true;
        return o;
    }

    protected static JsonObject Enumeracion(params string[] valores) =>
        new() { ["type"] = "STRING", ["enum"] = new JsonArray(valores.Select(v => (JsonNode)JsonValue.Create(v)!).ToArray()) };

    protected static JsonObject Lista(JsonObject item) => new() { ["type"] = "ARRAY", ["items"] = item };

    protected static JsonObject Objeto(Dictionary<string, JsonObject> propiedades, string[] requeridos)
    {
        var props = new JsonObject();
        foreach (var (k, v) in propiedades) props[k] = v;
        return new JsonObject
        {
            ["type"]             = "OBJECT",
            ["properties"]       = props,
            ["required"]         = new JsonArray(requeridos.Select(r => (JsonNode)JsonValue.Create(r)!).ToArray()),
            ["propertyOrdering"] = new JsonArray(propiedades.Keys.Select(k => (JsonNode)JsonValue.Create(k)!).ToArray()),
        };
    }

    protected static JsonObject Objeto(Dictionary<string, JsonObject> propiedades) => Objeto(propiedades, []);

    protected static string? Cadena(JsonObject o, string k) =>
        o[k] is JsonValue v && v.TryGetValue<string>(out var s) && !string.IsNullOrWhiteSpace(s) ? s.Trim() : null;

    protected static decimal? Numero(JsonObject o, string k)
    {
        if (o[k] is not JsonValue v) return null;
        if (v.TryGetValue<decimal>(out var d)) return d;
        if (v.TryGetValue<double>(out var x) && double.IsFinite(x)) return (decimal)x;
        if (v.TryGetValue<string>(out var s))
        {
            s = s.Replace(",", "").Replace("S/", "").Replace("$", "").Trim();
            if (decimal.TryParse(s, NumberStyles.Number, CultureInfo.InvariantCulture, out d)) return d;
        }
        return null;
    }

    protected static bool? Logico(JsonObject o, string k) =>
        o[k] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;

    protected static DateTime? FechaIso(string? s) =>
        DateTime.TryParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var f) ? f : null;

    protected static decimal? Porcentaje(decimal? v) =>
        v is null ? null : Math.Round(Math.Clamp(v.Value <= 1 && v.Value > 0 ? v.Value * 100 : v.Value, 0, 100), 2);

    protected static string? Recortar(string? s, int max) => s is null ? null : s.Length > max ? s[..max] : s;
}
