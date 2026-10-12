using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Adaptador de OpenRUC: GET {UrlBase}api/ruc/{ruc}. Sin autenticación.
/// 200 = datos · 400 = formato inválido · 404 = no existe o persona natural · 429 = límite.
/// El HttpClient llega configurado (BaseAddress y Timeout) desde Program.cs.
/// </summary>
public class OpenRucProveedor(HttpClient http) : IProveedorRuc
{
    public string Nombre => "openruc";

    public bool Cubre(string ruc) => ruc.Length == 11 && ruc.StartsWith("20");

    public async Task<ResultadoProveedorRucDto> ConsultarAsync(string ruc, CancellationToken ct)
    {
        var reloj = Stopwatch.StartNew();
        int Ms() => (int)reloj.ElapsedMilliseconds;

        try
        {
            using var respuesta = await http.GetAsync($"api/ruc/{ruc}", ct);
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
                    return new(ResultadoConsultaProveedor.NoEncontrado, null, codigo, "No encontrado o fuera de alcance.", Ms());

                case HttpStatusCode.TooManyRequests:
                    return new(ResultadoConsultaProveedor.Limite, null, codigo, "Límite de consultas alcanzado (429).", Ms());

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

    /// <summary>Lee el JSON de forma tolerante (ignora campos extra del proveedor).</summary>
    internal static DatosRucProveedorDto? Leer(string json, string rucConsultado)
    {
        using var doc = JsonDocument.Parse(json);
        var raiz = doc.RootElement;
        if (raiz.ValueKind != JsonValueKind.Object) return null;

        string? Campo(string nombre) =>
            raiz.TryGetProperty(nombre, out var v) && v.ValueKind == JsonValueKind.String
                ? (string.IsNullOrWhiteSpace(v.GetString()) ? null : v.GetString()!.Trim())
                : null;

        var razon = Campo("razon_social");
        if (razon is null) return null;

        DateOnly? fecha = DateOnly.TryParseExact(Campo("as_of"), "yyyy-MM-dd",
            CultureInfo.InvariantCulture, DateTimeStyles.None, out var f) ? f : null;

        var ubigeo = Campo("ubigeo");
        if (ubigeo is not null && (ubigeo.Length != 6 || !ubigeo.All(char.IsDigit))) ubigeo = null;

        return new DatosRucProveedorDto(
            Ruc:         Campo("ruc") ?? rucConsultado,
            RazonSocial: razon,
            Estado:      Campo("estado"),
            Condicion:   Campo("condicion"),
            Direccion:   Campo("direccion"),
            Ubigeo:      ubigeo,
            Fuente:      Campo("source") ?? "SUNAT",
            FechaDato:   fecha);
    }
}
