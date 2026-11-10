using System.Text.Json.Nodes;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Validación con IA (Google Gemini) de las capturas del registro fotográfico (HU-11 / HU-13): decide si la toma sirve como evidencia
/// (nítida, completa, legible) y lee lo que corresponda (datos de la placa, legibilidad y firma del informe, display encendido).
/// Si la IA falla o no responde devuelve "omitida": la captura se guarda igual y no se bloquea al técnico en planta.
/// </summary>
public class GeminiValidadorEvidencia(HttpClient http, ConfiguracionGemini configuracion)
    : GeminiClienteBase(http, configuracion), IValidadorEvidenciaIa
{
    private const string Instruccion = """
        Eres el validador de evidencias fotográficas de Total Weight (Perú), empresa de calibración y mantenimiento de balanzas, básculas
        e instrumentos de pesaje. Un técnico de campo tomó una foto con la cámara de su celular y debes decidir si sirve como evidencia.
        Reglas generales:
        - aprobada = true solo si la imagen cumple lo que se pide para esa evidencia y se ve con nitidez e iluminación suficientes.
        - Si rechazas: motivo = una oración corta en español que diga qué falla (por ejemplo "placa ilegible por reflejo y falta de nitidez. No se pudo leer la serie");
          sugerencia = una indicación corta para repetir la toma (por ejemplo "evita la luz directa y acércate a unos 30 cm"). Si apruebas, ambos null.
        - En "datos" llena solo lo que corresponda a la evidencia y deja null lo demás. No inventes: si un dato no se lee, null.
        - No juzgues la calidad del trabajo técnico, solo si la foto es válida como evidencia.
        """;

    private static JsonObject Esquema() => Objeto(new()
    {
        ["aprobada"]   = Tipo("BOOLEAN", false),
        ["motivo"]     = Tipo("STRING", true),
        ["sugerencia"] = Tipo("STRING", true),
        ["datos"]      = Objeto(new()
        {
            ["marca"]            = Tipo("STRING", true),
            ["modelo"]           = Tipo("STRING", true),
            ["serie"]            = Tipo("STRING", true),
            ["capacidad"]        = Tipo("STRING", true),
            ["legibilidad"]      = Enumeracion("BUENA", "REGULAR", "MALA"),
            ["hojaCompleta"]     = Tipo("BOOLEAN", true),
            ["firmaVisible"]     = Tipo("BOOLEAN", true),
            ["displayDetectado"] = Tipo("BOOLEAN", true),
            ["lectura"]          = Tipo("STRING", true),
        }),
    }, ["aprobada"]);

    private static string Pedido(SolicitudValidacionEvidenciaIa s) => s.Codigo switch
    {
        "placa" => $"Evidencia: PLACA DE IDENTIFICACIÓN del equipo. Aprueba solo si la placa se ve completa en el encuadre y se pueden leer la marca, el modelo y el número de serie (sin reflejos que oculten datos). "
                 + "Llena datos.marca, datos.modelo, datos.serie y datos.capacidad con lo que lees en la placa."
                 + (s.NumeroSerie is null ? "" : $" (El equipo registrado tiene serie «{s.NumeroSerie}»; solo para que sepas qué buscar, no la copies si no la lees.)"),
        "inicial" => "Evidencia: ESTADO INICIAL del equipo. Aprueba si se ve el equipo completo, enfocado y reconocible como balanza, báscula o instrumento de pesaje.",
        "desmontaje" => "Evidencia: PARTES DESMONTADAS del equipo. Aprueba si se ven las partes o componentes retirados del equipo, enfocados.",
        "abierto" => "Evidencia: INTERIOR DEL EQUIPO abierto. Aprueba si se ve el interior o los componentes internos con claridad.",
        "prueba" => "Evidencia: EQUIPO CON PESAS PATRÓN. Aprueba si se ve el equipo con pesas patrón sobre él o junto a él.",
        "final" => "Evidencia: EQUIPO TERMINADO Y LIMPIO. Aprueba si se ve el equipo completo, ordenado y limpio, enfocado.",
        "informe" => "Evidencia: FOTO DEL INFORME A MANO (hoja escrita por el técnico). Aprueba solo si el texto es legible, la hoja completa está en el encuadre y se ve la firma del técnico. "
                   + "Llena datos.legibilidad (BUENA, REGULAR o MALA), datos.hojaCompleta y datos.firmaVisible.",
        "encendido" => "Evidencia: CUADRO DE UN MICROVIDEO DEL ENCENDIDO del equipo. Aprueba si se ve el display o indicador de la balanza encendido. "
                     + "Llena datos.displayDetectado (true/false) y datos.lectura con lo que muestra el display (por ejemplo \"0 kg\") si se lee.",
        _ => "Evidencia fotográfica del equipo: aprueba si es nítida y muestra el equipo.",
    };

    public async Task<ResultadoValidacionEvidenciaIa> ValidarAsync(SolicitudValidacionEvidenciaIa s, CancellationToken ct)
    {
        if (!Disponible) return new("omitida", "La IA no está configurada.", null);

        var partes = new JsonArray
        {
            new JsonObject { ["inlineData"] = new JsonObject { ["mimeType"] = "image/jpeg", ["data"] = Convert.ToBase64String(s.Imagen) } },
            new JsonObject { ["text"] = Pedido(s) },
        };

        var (salida, error) = await GenerarAsync(Instruccion, partes, Esquema(), ct);
        if (error is not null) return new("omitida", error, null);

        try
        {
            var j = JsonNode.Parse(salida!)!.AsObject();
            var datos = j["datos"] as JsonObject;
            var aprobada = Logico(j, "aprobada") == true;
            // Encendido: además de la toma válida, el display tiene que haberse detectado
            if (s.Codigo == "encendido" && aprobada && datos is not null && Logico(datos, "displayDetectado") == false) aprobada = false;

            var motivo = Recortar(Cadena(j, "motivo"), 280);
            if (!aprobada && motivo is null)
                motivo = s.Codigo == "encendido" ? "No se detectó el display. Acércate y enfoca la pantalla del equipo." : "La IA no pudo validar la toma.";

            var extra = new JsonObject { ["sugerencia"] = Recortar(Cadena(j, "sugerencia"), 200) };
            if (datos is not null) foreach (var (k, v) in datos.ToList()) { datos.Remove(k); extra[k] = v; }
            return new(aprobada ? "aprobada" : "rechazada", aprobada ? null : motivo, extra.ToJsonString());
        }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or InvalidOperationException or FormatException)
        {
            return new("omitida", "La IA devolvió una respuesta que no se pudo interpretar.", null);
        }
    }
}

/// <summary>Sin API key de Gemini: la captura se guarda sin validar ("omitida"), igual que los demás asistentes de IA.</summary>
public class ValidadorEvidenciaIaNoConfigurado : IValidadorEvidenciaIa
{
    public Task<ResultadoValidacionEvidenciaIa> ValidarAsync(SolicitudValidacionEvidenciaIa solicitud, CancellationToken ct) =>
        Task.FromResult(new ResultadoValidacionEvidenciaIa("omitida", "La IA no está configurada.", null));
}
