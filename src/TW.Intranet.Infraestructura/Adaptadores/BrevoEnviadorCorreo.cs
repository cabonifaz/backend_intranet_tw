using System.Net.Http.Json;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Brevo — POST {UrlBase}v3/smtp/email con header "api-key". Responde 201 { messageId }.
/// El HttpClient llega con BaseAddress y Timeout desde Program.cs.
/// </summary>
public class BrevoEnviadorCorreo(HttpClient http, ConfiguracionCorreo configuracion) : IEnviadorCorreo
{
    public string Proveedor => "brevo";

    public async Task<ResultadoEnvioCorreoDto> EnviarAsync(MensajeCorreoDto mensaje, CancellationToken ct)
    {
        var cuerpo = new
        {
            sender      = new { email = configuracion.Remitente, name = configuracion.NombreRemitente },
            to          = new[] { string.IsNullOrWhiteSpace(mensaje.NombrePara)
                                      ? (object)new { email = mensaje.Para }
                                      : new { email = mensaje.Para, name = mensaje.NombrePara } },
            subject     = mensaje.Asunto,
            htmlContent = mensaje.Html,
            textContent = mensaje.Texto,
            tags        = new[] { "intranet-tw" },
        };

        try
        {
            using var solicitud = new HttpRequestMessage(HttpMethod.Post, "v3/smtp/email")
            {
                Content = JsonContent.Create(cuerpo),
            };
            solicitud.Headers.Add("api-key", configuracion.ApiKey);

            using var respuesta = await http.SendAsync(solicitud, ct);
            string texto = await respuesta.Content.ReadAsStringAsync(ct);

            if (respuesta.IsSuccessStatusCode)
                return new ResultadoEnvioCorreoDto(true, Proveedor, Leer(texto, "messageId"), null);

            int codigo = (int)respuesta.StatusCode;
            string detalle = Leer(texto, "message") ?? respuesta.ReasonPhrase ?? "";
            string error = codigo switch
            {
                401 => $"API key de Brevo inválida o IP no autorizada ({detalle})",
                402 => "Sin créditos de envío en Brevo (límite del plan alcanzado)",
                429 => "Límite de envíos de Brevo alcanzado; intente más tarde",
                _   => $"Brevo respondió HTTP {codigo}: {detalle}",
            };
            return new ResultadoEnvioCorreoDto(false, Proveedor, null, Recortar(error));
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            return new ResultadoEnvioCorreoDto(false, Proveedor, null, "Tiempo de espera agotado con Brevo");
        }
        catch (HttpRequestException ex)
        {
            return new ResultadoEnvioCorreoDto(false, Proveedor, null, Recortar($"No se pudo conectar con Brevo: {ex.Message}"));
        }
    }

    private static string? Leer(string json, string propiedad)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                   && doc.RootElement.TryGetProperty(propiedad, out var v)
                   && v.ValueKind == JsonValueKind.String
                ? v.GetString()
                : null;
        }
        catch (JsonException) { return null; }
    }

    private static string Recortar(string texto) => texto.Length <= 400 ? texto : texto[..400];
}

/// <summary>Se usa cuando no hay ApiKey: no envía nada y lo deja registrado como error.</summary>
public class EnviadorCorreoNoConfigurado : IEnviadorCorreo
{
    public string Proveedor => "no_configurado";

    public Task<ResultadoEnvioCorreoDto> EnviarAsync(MensajeCorreoDto mensaje, CancellationToken ct)
        => Task.FromResult(new ResultadoEnvioCorreoDto(false, Proveedor, null,
            "El servicio de correo no está configurado (falta Correo__ApiKey o Correo__Remitente en Railway)"));
}
