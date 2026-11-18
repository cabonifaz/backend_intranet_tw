using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Envía las notificaciones a la bandeja del teléfono con el servicio de push de Expo (que las entrega por Firebase en Android).
/// Hasta 100 por solicitud. "Crítica" usa el canal "criticas" (suena y aparece como urgente); el resto, el canal "general".
/// Un 429 o un 5xx se reintenta una vez; un token con "DeviceNotRegistered" vuelve en <see cref="ResultadoEnvioPushDto.TokensInvalidos"/>.
/// </summary>
public class ExpoEnviadorPushMovil(HttpClient http, ConfiguracionPushMovil configuracion) : IEnviadorPushMovil
{
    private const string Url = "https://exp.host/--/api/v2/push/send";

    public async Task<ResultadoEnvioPushDto> EnviarAsync(IReadOnlyList<MensajePushDto> mensajes, CancellationToken ct)
    {
        var enviados  = 0;
        var invalidos = new List<string>();
        string? error = null;

        foreach (var lote in mensajes.Chunk(100))
        {
            try
            {
                var cuerpo = lote.Select(m => new
                {
                    to        = m.Token,
                    title     = m.Titulo,
                    body      = m.Cuerpo,
                    sound     = "default",
                    priority  = "high",
                    channelId = m.Prioridad == "critica" ? "criticas" : "general",
                    data      = new { idNotificacion = m.IdNotificacion, prioridad = m.Prioridad },
                }).ToList();

                using var respuesta = await PublicarAsync(cuerpo, ct);
                if (!respuesta.IsSuccessStatusCode)
                {
                    error = $"El servicio de push respondió {(int)respuesta.StatusCode}.";
                    continue;
                }

                using var doc = await JsonDocument.ParseAsync(await respuesta.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
                if (!doc.RootElement.TryGetProperty("data", out var tickets) || tickets.ValueKind != JsonValueKind.Array) continue;

                var i = 0;
                foreach (var ticket in tickets.EnumerateArray())
                {
                    if (i >= lote.Length) break;

                    var estado = ticket.TryGetProperty("status", out var s) ? s.GetString() : null;
                    if (estado == "ok")
                        enviados++;
                    else if (ticket.TryGetProperty("details", out var d) && d.TryGetProperty("error", out var e) && e.GetString() == "DeviceNotRegistered")
                        invalidos.Add(lote[i].Token);
                    else
                        error = ticket.TryGetProperty("message", out var msg) ? msg.GetString() : "El servicio de push rechazó una notificación.";
                    i++;
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                error = ex.Message;
            }
        }

        return new ResultadoEnvioPushDto(enviados, invalidos, error);
    }

    private async Task<HttpResponseMessage> PublicarAsync(object cuerpo, CancellationToken ct)
    {
        HttpResponseMessage? respuesta = null;
        for (var intento = 0; intento < 2; intento++)
        {
            respuesta?.Dispose();

            using var solicitud = new HttpRequestMessage(HttpMethod.Post, Url) { Content = JsonContent.Create(cuerpo) };
            solicitud.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            if (!string.IsNullOrWhiteSpace(configuracion.AccessToken))
                solicitud.Headers.Authorization = new AuthenticationHeaderValue("Bearer", configuracion.AccessToken);

            respuesta = await http.SendAsync(solicitud, ct);
            var reintentable = (int)respuesta.StatusCode == 429 || (int)respuesta.StatusCode >= 500;
            if (!reintentable) break;
            if (intento == 0) await Task.Delay(TimeSpan.FromSeconds(2), ct);
        }
        return respuesta!;
    }
}
