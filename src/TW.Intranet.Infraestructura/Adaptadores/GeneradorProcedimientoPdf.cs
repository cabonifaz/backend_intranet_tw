using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// App Mobile HU-24 — PDF A4 del procedimiento (QuestPDF) armado con lo registrado en la intranet: código, descripción, versión vigente, año, autor y norma,
/// tipo, formato digital ISO, fecha de actualización e historial de versiones. La app lo descarga para leerlo sin conexión.
/// </summary>
public class GeneradorProcedimientoPdf : IGeneradorProcedimientoPdf
{
    private const string Primario = "#0057B8";
    private const string Titulo   = "#0F172A";
    private const string Gris     = "#64748B";
    private const string Borde    = "#E2E8F0";
    private const string Fondo    = "#F1F5F9";

    public byte[] Generar(ProcedimientoMovilDto p, DateTime generadoEnLima)
    {
        var tipo = p.Tipo switch { "calibracion" => "Calibración", "verificacion" => "Verificación", _ => null };
        return Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(36);
                page.DefaultTextStyle(t => t.FontSize(10.5f).FontColor(Titulo));

                page.Header().Column(col =>
                {
                    col.Item().Text("PROCEDIMIENTO METROLÓGICO").FontSize(11).Bold().FontColor(Gris);
                    col.Item().Text(p.Codigo).FontSize(24).Bold().FontColor(Primario);
                    col.Item().Text($"Versión {p.Version} · vigente").FontColor(Gris);
                    col.Item().PaddingTop(8).LineHorizontal(1).LineColor(Borde);
                });

                page.Content().PaddingTop(12).Column(col =>
                {
                    col.Spacing(14);

                    col.Item().Background(Fondo).Padding(12).Column(d =>
                    {
                        d.Item().Text("DESCRIPCIÓN").FontSize(8.5f).Bold().FontColor(Gris);
                        d.Item().PaddingTop(2).Text(p.Descripcion).FontSize(12);
                    });

                    col.Item().Table(t =>
                    {
                        t.ColumnsDefinition(c => { c.ConstantColumn(130); c.RelativeColumn(); });
                        void Fila(string k, string? v)
                        {
                            if (string.IsNullOrWhiteSpace(v)) return;
                            t.Cell().BorderBottom(1).BorderColor(Borde).PaddingVertical(6).Text(k.ToUpperInvariant()).FontSize(8.5f).Bold().FontColor(Gris);
                            t.Cell().BorderBottom(1).BorderColor(Borde).PaddingVertical(6).Text(v);
                        }
                        Fila("Código", p.Codigo);
                        Fila("Versión", $"{p.Version} · vigente");
                        Fila("Año", p.Anio.ToString());
                        Fila("Autor", p.AutorNorma);
                        Fila("Norma base", p.NormaBase);
                        Fila("Tipo", tipo);
                        Fila("Formato digital ISO", p.FormatoDigitalIso ? "Sí" : "No");
                        Fila("Alcance", p.Alcance);
                        Fila("Aprobado por", p.AprobadoPor);
                        Fila("Actualizado", FechaDma(p.Actualizado));
                    });

                    col.Item().Column(h =>
                    {
                        h.Spacing(4);
                        h.Item().Text("HISTORIAL DE VERSIONES").FontSize(8.5f).Bold().FontColor(Gris);
                        h.Item().Text($"Versión {p.Version} — vigente (actualizada el {FechaDma(p.Actualizado)})").Bold();
                        foreach (var v in p.Historial)
                            h.Item().Text($"Versión {v.Version} — reemplazada{(v.ReemplazadaEl is null ? "" : $" el {FechaDma(v.ReemplazadaEl)}")}; ya no se puede usar").FontColor(Gris);
                    });
                });

                page.Footer().Column(f =>
                {
                    f.Item().LineHorizontal(1).LineColor(Borde);
                    f.Item().PaddingTop(4).Row(r =>
                    {
                        r.RelativeItem().Text($"Total Weight · documento generado el {generadoEnLima:dd/MM/yyyy HH:mm} desde la app de campo").FontSize(8).FontColor(Gris);
                        r.AutoItem().Text(x =>
                        {
                            x.DefaultTextStyle(s => s.FontSize(8).FontColor(Gris));
                            x.Span("Pág. ");
                            x.CurrentPageNumber();
                            x.Span(" / ");
                            x.TotalPages();
                        });
                    });
                });
            });
        }).GeneratePdf();
    }

    /// <summary>"2026-10-12" → "12/10/2026".</summary>
    private static string FechaDma(string? iso)
        => DateTime.TryParse(iso, out var f) ? f.ToString("dd/MM/yyyy") : "—";
}
