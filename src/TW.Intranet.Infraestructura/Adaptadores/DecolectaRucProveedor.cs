using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Adaptador de Decolecta (antes apis.net.pe): GET {UrlBase}v1/sunat/ruc?numero={ruc} con "Authorization: Bearer {token}".
/// Cubre todos los RUC del padrón de SUNAT, incluidas las personas naturales con negocio (RUC 10).
/// Se registra después de OpenRUC: para RUC 20 solo se usa si OpenRUC no responde o llegó a su límite.
/// 200 = datos · 404/422 = no existe · 401/403 = token inválido · 429 = límite del plan.
/// El HttpClient llega configurado (BaseAddress, Timeout y token) desde Program.cs.
/// </summary>
public class DecolectaRucProveedor(HttpClient http) : IProveedorRuc
{
    public string Nombre => "decolecta";

    public bool Cubre(string ruc) => ruc.Length == 11;

    public async Task<ResultadoProveedorRucDto> ConsultarAsync(string ruc, CancellationToken ct)
    {
        var reloj = Stopwatch.StartNew();
        int Ms() => (int)reloj.ElapsedMilliseconds;

        try
        {
            using var respuesta = await http.GetAsync($"v1/sunat/ruc?numero={ruc}", ct);
            int codigo = (int)respuesta.StatusCode;

            switch (respuesta.StatusCode)
            {
                case HttpStatusCode.OK:
                    var cuerpo = await respuesta.Content.ReadAsStringAsync(ct);
                    var datos  = Leer(cuerpo, ruc);
                    return datos is null
                        ? new(ResultadoConsultaProveedor.Error, null, codigo, "Respuesta sin razón social.", Ms())
                        : new(ResultadoConsultaProveedor.Encontrado, datos, codigo, null, Ms());

                case HttpStatusCode.NotFound:
                case HttpStatusCode.UnprocessableEntity:
                    return new(ResultadoConsultaProveedor.NoEncontrado, null, codigo, "RUC no encontrado en el padrón.", Ms());

                case HttpStatusCode.TooManyRequests:
                    return new(ResultadoConsultaProveedor.Limite, null, codigo, "Límite de consultas del plan alcanzado (429).", Ms());

                case HttpStatusCode.Unauthorized:
                case HttpStatusCode.Forbidden:
                    return new(ResultadoConsultaProveedor.Error, null, codigo, "Token de Decolecta inválido o vencido.", Ms());

                default:
                    return new(ResultadoConsultaProveedor.Error, null, codigo, $"HTTP {codigo}", Ms());
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            return new(ResultadoConsultaProveedor.Error, null, null, "Tiempo de espera agotado.", Ms());
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException)
        {
            return new(ResultadoConsultaProveedor.Error, null, null, ex.Message, Ms());
        }
    }

    /// <summary>Configura el token en el HttpClient (encabezado Authorization: Bearer).</summary>
    public static void ConfigurarToken(HttpClient cliente, string token) =>
        cliente.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Trim());

    /// <summary>
    /// Lee el JSON de forma tolerante. Decolecta devuelve "-" en los campos vacíos (frecuente en la dirección de las
    /// personas naturales): se tratan como vacíos.
    /// </summary>
    internal static DatosRucProveedorDto? Leer(string json, string rucConsultado)
    {
        using var doc = JsonDocument.Parse(json);
        var raiz = doc.RootElement;
        if (raiz.ValueKind != JsonValueKind.Object) return null;

        string? Campo(string nombre)
        {
            if (!raiz.TryGetProperty(nombre, out var v) || v.ValueKind != JsonValueKind.String) return null;
            var texto = v.GetString()?.Trim();
            return string.IsNullOrEmpty(texto) || texto == "-" ? null : texto;
        }

        var razon = Campo("razon_social");
        if (razon is null) return null;

        var ubigeo = Campo("ubigeo");
        if (ubigeo is not null && (ubigeo.Length != 6 || !ubigeo.All(char.IsDigit))) ubigeo = null;

        // La dirección viene con espacios dobles y guiones de relleno ("JR. LIMA NRO 123 - - "): se limpia.
        var direccion = Campo("direccion");
        if (direccion is not null)
        {
            direccion = string.Join(' ', direccion.Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(p => p != "-"));
            if (direccion.Length == 0) direccion = null;
        }

        return new DatosRucProveedorDto(
            Ruc:         Campo("numero_documento") ?? rucConsultado,
            RazonSocial: razon,
            Estado:      Campo("estado"),
            Condicion:   Campo("condicion"),
            Direccion:   direccion,
            Ubigeo:      ubigeo,
            Fuente:      "SUNAT",
            FechaDato:   null);
    }
}
