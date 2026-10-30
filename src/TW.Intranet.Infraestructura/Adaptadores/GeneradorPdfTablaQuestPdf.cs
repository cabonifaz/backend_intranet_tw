using System.Globalization;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>PDF A4 horizontal con una tabla (QuestPDF): título, subtítulo, encabezado repetido y número de página.</summary>
public class GeneradorPdfTablaQuestPdf : IGeneradorPdfTabla
{
    private const string ColorPrimario  = "#2563EB";
    private const string ColorTitulo    = "#0F172A";
    private const string ColorGrisTexto = "#64748B";
    private const string ColorGrisBorde = "#E2E8F0";
    private const string ColorFondo     = "#EFF4FF";

    private static readonly CultureInfo CulturaPe = new("es-PE");

    public byte[] Generar(DocumentoTablaPdf documento)
    {
        var tabla = documento.Tabla;
        return Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4.Landscape());
                page.Margin(24);
                page.DefaultTextStyle(t => t.FontSize(8).FontColor(ColorTitulo));

                page.Header().Column(col =>
                {
                    col.Item().Text(documento.Titulo).FontSize(14).Bold().FontColor(ColorPrimario);
                    if (!string.IsNullOrWhiteSpace(documento.Subtitulo))
                        col.Item().Text(documento.Subtitulo).FontSize(9).FontColor(ColorGrisTexto);
                    col.Item().PaddingBottom(6);
                });

                page.Content().Table(t =>
                {
                    t.ColumnsDefinition(c =>
                    {
                        foreach (var _ in tabla.Encabezados) c.RelativeColumn();
                    });

                    t.Header(h =>
                    {
                        foreach (var e in tabla.Encabezados)
                            h.Cell().Background(ColorFondo).BorderBottom(1).BorderColor(ColorGrisBorde).Padding(4)
                             .Text(e).Bold().FontSize(8);
                    });

                    foreach (var fila in tabla.Filas)
                        foreach (var valor in fila)
                            t.Cell().BorderBottom(0.5f).BorderColor(ColorGrisBorde).Padding(4).Text(Formato(valor));
                });

                page.Footer().Row(r =>
                {
                    r.RelativeItem().Text(documento.PiePagina ?? $"Generado el {DateTime.Now:dd/MM/yyyy HH:mm}")
                     .FontSize(7).FontColor(ColorGrisTexto);
                    r.AutoItem().Text(x =>
                    {
                        x.DefaultTextStyle(s => s.FontSize(7).FontColor(ColorGrisTexto));
                        x.Span("Página ");
                        x.CurrentPageNumber();
                        x.Span(" de ");
                        x.TotalPages();
                    });
                });
            });
        }).GeneratePdf();
    }

    private static string Formato(object? valor) => valor switch
    {
        null       => "",
        DateTime d => d.TimeOfDay == TimeSpan.Zero ? d.ToString("dd/MM/yyyy") : d.ToString("dd/MM/yyyy HH:mm"),
        decimal m  => m.ToString("N1", CulturaPe),
        bool b     => b ? "Sí" : "No",
        _          => Convert.ToString(valor, CulturaPe) ?? "",
    };
}
