using System.Globalization;
using System.Text;
using System.Text.Json;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// App Mobile HU-17 — PDF A4 de la constancia de servicio (QuestPDF): datos del cliente y del servicio, equipos intervenidos, estado de los informes técnicos y las
/// firmas (la del cliente y la de cada responsable) dibujadas como VECTORES a partir de los trazos guardados (no hay imagen de la firma).
/// </summary>
public class GeneradorConstanciaPdf : IGeneradorConstanciaPdf
{
    private const string Primario = "#0057B8";
    private const string Titulo   = "#0F172A";
    private const string Gris     = "#64748B";
    private const string Borde    = "#E2E8F0";
    /// <summary>Relación ancho / alto del lienzo de firma de la app (los trazos están normalizados a ese rectángulo).</summary>
    public const double AspectoFirma = 2.5;

    /// <summary>SVG de una firma: un camino por trazo, con el lienzo de 250 × 100.</summary>
    public static string SvgFirma(JsonElement? trazos)
    {
        var sb = new StringBuilder("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 250 100\" width=\"250\" height=\"100\"><g fill=\"none\" stroke=\"#0F172A\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">");
        if (trazos is { ValueKind: JsonValueKind.Object } raiz && raiz.TryGetProperty("trazos", out var lista) && lista.ValueKind == JsonValueKind.Array)
            foreach (var t in lista.EnumerateArray())
            {
                if (t.ValueKind != JsonValueKind.Array) continue;
                var d = new StringBuilder();
                var primero = true;
                foreach (var p in t.EnumerateArray())
                {
                    if (p.ValueKind != JsonValueKind.Array || p.GetArrayLength() != 2 || !p[0].TryGetDouble(out var x) || !p[1].TryGetDouble(out var y)) continue;
                    d.Append(primero ? 'M' : 'L').Append((x * 250).ToString("0.##", CultureInfo.InvariantCulture)).Append(' ').Append((y * 100).ToString("0.##", CultureInfo.InvariantCulture)).Append(' ');
                    primero = false;
                }
                if (d.Length > 0) sb.Append("<path d=\"").Append(d.ToString().TrimEnd()).Append("\"/>");
            }
        return sb.Append("</g></svg>").ToString();
    }

    public byte[] Generar(DatosConstanciaPdf datos)
    {
        var c = datos.Constancia.Cabecera;
        var informesFirmados = $"{c.Firmados} de {c.Informes}";
        return Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(36);
                page.DefaultTextStyle(t => t.FontSize(9.5f).FontColor(Titulo));

                page.Header().Column(col =>
                {
                    col.Item().Text("CONSTANCIA DE SERVICIO").FontSize(18).Bold().FontColor(Primario);
                    col.Item().Text($"Orden de servicio {c.NumeroOs}{(string.IsNullOrWhiteSpace(c.NumeroRq) ? "" : $" · RQ {c.NumeroRq}")}").FontColor(Gris);
                    col.Item().PaddingBottom(8).LineHorizontal(1).LineColor(Borde);
                });

                page.Content().Column(col =>
                {
                    col.Spacing(10);
                    col.Item().Column(d =>
                    {
                        d.Item().Text(c.Cliente ?? "—").FontSize(12).Bold();
                        if (!string.IsNullOrWhiteSpace(c.Direccion)) d.Item().Text(c.Direccion).FontColor(Gris);
                        if (!string.IsNullOrWhiteSpace(c.ContactoNombre))
                            d.Item().Text($"Contacto: {c.ContactoNombre}{(string.IsNullOrWhiteSpace(c.ContactoCargo) ? "" : $" · {c.ContactoCargo}")}{(string.IsNullOrWhiteSpace(c.ContactoTelefono) ? "" : $" · {c.ContactoTelefono}")}");
                        d.Item().Text($"Fecha: {c.Fecha ?? "—"} · Informes técnicos firmados: {informesFirmados}").FontColor(Gris);
                    });

                    col.Item().Text("Equipos intervenidos").Bold().FontSize(11).FontColor(Primario);
                    col.Item().Table(t =>
                    {
                        t.ColumnsDefinition(cd => { cd.RelativeColumn(3); cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); });
                        t.Header(h =>
                        {
                            foreach (var e in new[] { "Equipo", "Marca · modelo", "Serie · código", "Certificado" })
                                h.Cell().Background("#EFF4FF").BorderBottom(1).BorderColor(Borde).Padding(4).Text(e).Bold().FontSize(8.5f);
                        });
                        foreach (var e in datos.Constancia.Equipos)
                        {
                            t.Cell().BorderBottom(1).BorderColor(Borde).Padding(4).Text(e.Equipo ?? "—");
                            t.Cell().BorderBottom(1).BorderColor(Borde).Padding(4).Text($"{e.Marca} {e.Modelo}".Trim());
                            t.Cell().BorderBottom(1).BorderColor(Borde).Padding(4).Text($"{e.Serie ?? "—"} · {e.Codigo ?? "—"}");
                            t.Cell().BorderBottom(1).BorderColor(Borde).Padding(4).Text(e.Certificado ?? "—");
                        }
                    });

                    col.Item().Text("Firmas").Bold().FontSize(11).FontColor(Primario);
                    col.Item().Row(row =>
                    {
                        row.Spacing(12);
                        row.RelativeItem().Border(1).BorderColor(Borde).Padding(8).Column(f =>
                        {
                            f.Item().Text("Cliente").Bold();
                            if (c.Trazos is not null) f.Item().Height(60).Svg(SvgFirma(c.Trazos));
                            else f.Item().Height(60).AlignMiddle().Text(c.TieneFoto ? "Firmada en el formato físico." : "—").FontColor(Gris);
                            f.Item().Text($"{c.Firmante ?? "—"}{(c.FirmadoEn is { } h ? $" · {h:dd/MM/yyyy HH:mm}" : "")}").FontColor(Gris).FontSize(8.5f);
                        });
                        row.RelativeItem().Column(r =>
                        {
                            r.Spacing(6);
                            foreach (var x in datos.Firmas.Responsables)
                                r.Item().Border(1).BorderColor(Borde).Padding(6).Column(f =>
                                {
                                    f.Item().Text($"{x.Nombre}{(string.IsNullOrWhiteSpace(x.Cargo) ? "" : $" · {x.Cargo}")}").Bold().FontSize(9);
                                    f.Item().Text($"Informes: {x.Informes ?? "—"}").FontColor(Gris).FontSize(8);
                                    if (x.Trazos is not null) f.Item().Height(36).Svg(SvgFirma(x.Trazos));
                                    else f.Item().Text(x.Firma == "firmado" ? "Firmado en el formato físico." : "Firma pendiente.").FontColor(Gris).FontSize(8.5f);
                                    if (x.FirmadoEn is { } h) f.Item().Text($"{h:dd/MM/yyyy HH:mm}").FontColor(Gris).FontSize(8);
                                });
                        });
                    });
                });

                page.Footer().AlignCenter().Text("Documento generado por la app de campo de Total Weight. Las firmas de dispositivo se conservan como trazos digitales.").FontSize(7.5f).FontColor(Gris);
            });
        }).GeneratePdf();
    }
}
