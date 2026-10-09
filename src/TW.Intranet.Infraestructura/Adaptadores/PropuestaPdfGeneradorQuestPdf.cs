using System.Globalization;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Generador del PDF comercial de la propuesta usando QuestPDF.
/// Secciones: carátula + introducción + propuesta técnica + opcionales + detalle +
/// recomendaciones + forma de pago + suministros cliente + condiciones + listado de
/// equipos + resumen económico + firma.
/// Las secciones condicionales (opcionales, detalle, recomendaciones, suministros, condiciones)
/// solo se imprimen si están en Propuesta.SeccionesActivas.
/// </summary>
public class PropuestaPdfGeneradorQuestPdf : IPropuestaPdfGenerador
{
    // Paleta corporativa TW (misma del front).
    private const string ColorPrimario    = "#2563EB"; // azul
    private const string ColorPrimarioOsc = "#1D4ED8";
    private const string ColorTitulo      = "#0F172A";
    private const string ColorSubtitulo   = "#475569";
    private const string ColorGrisTexto   = "#64748B";
    private const string ColorGrisBorde   = "#E2E8F0";
    private const string ColorFondoClaro  = "#F8FAFC";
    private const string ColorFondoTabla  = "#EFF4FF";
    private const string ColorVerde       = "#16A34A";
    private const string ColorRojo        = "#DC2626";

    private static readonly CultureInfo CulturaPe = new("es-PE");

    public byte[] Generar(PropuestaDetalleModalDto detalle)
    {
        return Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(1.5f, Unit.Centimetre);
                // Lato viene embebida en QuestPDF (funciona en Windows, Linux, Docker sin instalar fuentes).
                page.DefaultTextStyle(x => x.FontSize(10).FontColor(ColorTitulo).FontFamily("Lato"));

                page.Header().Element(ComponerHeader(detalle));
                page.Content().Element(c => ComponerContenido(c, detalle));
                page.Footer().Element(ComponerFooter);
            });
        }).GeneratePdf();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // HEADER (todas las páginas: código propuesta + versión)
    // ══════════════════════════════════════════════════════════════════════════
    private Action<IContainer> ComponerHeader(PropuestaDetalleModalDto d) => container =>
    {
        var p = d.Propuesta;
        container.PaddingBottom(10).BorderBottom(1).BorderColor(ColorGrisBorde).Row(row =>
        {
            row.RelativeItem().Column(col =>
            {
                col.Item().Text("TOTAL WEIGHT")
                    .FontSize(14).Bold().FontColor(ColorPrimario);
                col.Item().Text("Propuesta Técnico - Económica")
                    .FontSize(9).FontColor(ColorGrisTexto);
            });
            row.ConstantItem(140).AlignRight().Column(col =>
            {
                col.Item().Text($"{p.Numero} · v{p.Version}")
                    .FontSize(11).SemiBold().FontColor(ColorTitulo);
                col.Item().Text(FormatearFecha(p.FechaCreacion))
                    .FontSize(9).FontColor(ColorGrisTexto);
            });
        });
    };

    // ══════════════════════════════════════════════════════════════════════════
    // FOOTER (número de página)
    // ══════════════════════════════════════════════════════════════════════════
    private void ComponerFooter(IContainer container)
    {
        container.PaddingTop(10).BorderTop(1).BorderColor(ColorGrisBorde).Row(row =>
        {
            row.RelativeItem().Text(t =>
            {
                t.DefaultTextStyle(s => s.FontSize(8).FontColor(ColorGrisTexto));
                t.Span("Total Weight S.A.C.  ·  ");
                t.Span("Documento generado automáticamente");
            });
            row.ConstantItem(80).AlignRight().Text(t =>
            {
                t.DefaultTextStyle(s => s.FontSize(8).FontColor(ColorGrisTexto));
                t.Span("Página ");
                t.CurrentPageNumber();
                t.Span(" / ");
                t.TotalPages();
            });
        });
    }

    // ══════════════════════════════════════════════════════════════════════════
    // CONTENIDO
    // ══════════════════════════════════════════════════════════════════════════
    private void ComponerContenido(IContainer container, PropuestaDetalleModalDto d)
    {
        var p         = d.Propuesta;
        var secciones = p.SeccionesActivas ?? new List<string>();

        container.PaddingVertical(10).Column(col =>
        {
            col.Spacing(14);

            // 1. Carátula
            col.Item().Element(c => ComponerCaratula(c, d));

            // 2. Introducción
            if (!string.IsNullOrWhiteSpace(p.Introduccion))
                col.Item().Element(c => ComponerSeccion(c, "Introducción", p.Introduccion!));

            // 3. Propuesta técnica
            col.Item().Element(c => ComponerTablaItems(c, "Propuesta Técnica", ItemsPorSeccion(p.Items, "principal"), p));

            // 4. Opcionales
            if (secciones.Contains("opcionales"))
            {
                var opcionales = ItemsPorSeccion(p.Items, "opcional");
                if (opcionales.Count > 0)
                    col.Item().Element(c => ComponerTablaItems(c, "Opcionales", opcionales, p));
            }

            // 5. Detalle (textos base)
            if (secciones.Contains("detalle"))
                col.Item().Element(c => ComponerTextosSeccion(c, "Detalle Técnico", TextosPorSeccion(p.Textos, "detalle")));

            // 6. Recomendaciones
            if (secciones.Contains("recomendaciones"))
                col.Item().Element(c => ComponerTextosSeccion(c, "Recomendaciones", TextosPorSeccion(p.Textos, "recomendaciones")));

            // 7. Forma de pago
            col.Item().Element(c => ComponerFormasPago(c, p));

            // 8. Suministros Cliente
            if (secciones.Contains("suministros_cliente"))
                col.Item().Element(c => ComponerTextosSeccion(c, "Suministros a Cargo del Cliente", TextosPorSeccion(p.Textos, "suministros_cliente")));

            // 9. Condiciones
            if (secciones.Contains("condiciones"))
                col.Item().Element(c => ComponerTextosSeccion(c, "Condiciones del Servicio", TextosPorSeccion(p.Textos, "condiciones")));

            // 10. Listado de equipos
            if (p.Equipos.Count > 0)
                col.Item().Element(c => ComponerTablaEquipos(c, p.Equipos));

            // 11-12. Resumen económico + Firma (van juntos al final, nunca se separan).
            col.Item().Element(c => ComponerCierre(c, p));
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CARÁTULA
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerCaratula(IContainer container, PropuestaDetalleModalDto d)
    {
        var p = d.Propuesta;
        container.ShowEntire().Background(ColorFondoClaro).Padding(15).Column(col =>
        {
            col.Spacing(8);
            col.Item().Text($"{p.Numero}  ·  Versión {p.Version}")
                .FontSize(20).Bold().FontColor(ColorPrimario);
            col.Item().PaddingTop(4).Row(row =>
            {
                row.RelativeItem().Column(c =>
                {
                    c.Item().Text("CLIENTE").FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
                    c.Item().Text(p.RazonSocial).FontSize(12).SemiBold().FontColor(ColorTitulo);
                    c.Item().Text($"RUC: {p.Ruc}").FontSize(9).FontColor(ColorSubtitulo);
                    if (!string.IsNullOrWhiteSpace(p.NombreContacto))
                    {
                        c.Item().PaddingTop(6).Text("CONTACTO").FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
                        c.Item().Text(p.NombreContacto!).FontSize(10).FontColor(ColorTitulo);
                        if (!string.IsNullOrWhiteSpace(p.CargoContacto))
                            c.Item().Text(p.CargoContacto!).FontSize(9).FontColor(ColorGrisTexto);
                    }
                });
                row.ConstantItem(180).Column(c =>
                {
                    FilaDato(c, "N° REQUERIMIENTO", p.NumeroRequerimiento ?? "—");
                    FilaDato(c, "COMERCIAL",        p.NombreResponsable  ?? "—");
                    FilaDato(c, "FECHA",            FormatearFecha(p.FechaCreacion));
                    if (!string.IsNullOrEmpty(d.NumeroContratoMarco))
                        FilaDato(c, "CONTRATO",     d.NumeroContratoMarco);
                });
            });
            if (!string.IsNullOrWhiteSpace(p.Referencia))
            {
                col.Item().PaddingTop(4).BorderTop(1).BorderColor(ColorGrisBorde).PaddingTop(6).Column(c =>
                {
                    c.Item().Text("REFERENCIA").FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
                    c.Item().Text(p.Referencia!).FontSize(10).FontColor(ColorTitulo);
                });
            }
        });
    }

    private static void FilaDato(ColumnDescriptor col, string label, string valor)
    {
        col.Item().PaddingBottom(4).Column(c =>
        {
            c.Item().Text(label).FontSize(8).FontColor("#64748B").LetterSpacing(0.5f);
            c.Item().Text(valor).FontSize(10).SemiBold().FontColor("#0F172A");
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // SECCIÓN GENÉRICA (introducción, etc.)
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerSeccion(IContainer container, string titulo, string contenido)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text(titulo).FontSize(13).Bold().FontColor(ColorPrimario);
            col.Item().Text(contenido).FontSize(10).FontColor(ColorTitulo).LineHeight(1.4f);
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // TABLA DE ITEMS
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerTablaItems(IContainer container, string titulo, List<PropuestaItemDto> items, PropuestaDetalleDto p)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text(titulo).FontSize(13).Bold().FontColor(ColorPrimario);

            if (items.Count == 0)
            {
                col.Item().Text("Sin ítems en esta sección.").FontSize(9).Italic().FontColor(ColorGrisTexto);
                return;
            }

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(c =>
                {
                    c.ConstantColumn(25);  // #
                    c.RelativeColumn(5);   // Descripción
                    c.ConstantColumn(40);  // Cant
                    c.ConstantColumn(55);  // P.Unit
                    c.ConstantColumn(45);  // Dcto
                    c.ConstantColumn(60);  // Subtotal
                });

                table.Header(header =>
                {
                    header.Cell().Element(CeldaHeader).Text("#");
                    header.Cell().Element(CeldaHeader).Text("Descripción");
                    header.Cell().Element(CeldaHeader).AlignRight().Text("Cant.");
                    header.Cell().Element(CeldaHeader).AlignRight().Text("P. Unit.");
                    header.Cell().Element(CeldaHeader).AlignRight().Text("Dcto.");
                    header.Cell().Element(CeldaHeader).AlignRight().Text("Subtotal");
                });

                int n = 0;
                foreach (var it in items.OrderBy(i => i.Orden))
                {
                    if (it.EsEspaciado) continue;
                    n++;
                    table.Cell().Element(CeldaFila).Text(n.ToString());
                    table.Cell().Element(CeldaFila).Column(c =>
                    {
                        c.Item().Text(it.Descripcion ?? "—").FontSize(9);
                        if (!string.IsNullOrWhiteSpace(it.Alcance))
                            c.Item().Text(it.Alcance!).FontSize(8).FontColor(ColorGrisTexto);
                    });
                    table.Cell().Element(CeldaFila).AlignRight().Text(FormatearDecimal(it.Cantidad * it.Frecuencia));
                    table.Cell().Element(CeldaFila).AlignRight().Text(FormatearMoneda(it.PrecioUnitario, p.MonedaSimbolo));
                    table.Cell().Element(CeldaFila).AlignRight().Text(it.Descuento > 0 ? FormatearMoneda(it.Descuento, p.MonedaSimbolo) : "—");
                    table.Cell().Element(CeldaFila).AlignRight().Text(FormatearMoneda(it.Subtotal, p.MonedaSimbolo)).SemiBold();
                }
            });
        });
    }

    private IContainer CeldaHeader(IContainer c)
        => c.Background(ColorFondoTabla).Padding(6).DefaultTextStyle(s => s.FontSize(9).SemiBold().FontColor(ColorPrimarioOsc));

    private IContainer CeldaFila(IContainer c)
        => c.BorderBottom(1).BorderColor(ColorGrisBorde).Padding(6).DefaultTextStyle(s => s.FontSize(9));

    // ──────────────────────────────────────────────────────────────────────────
    // TEXTOS POR SECCIÓN (detalle, recomendaciones, suministros, condiciones)
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerTextosSeccion(IContainer container, string titulo, List<PropuestaTextoDto> textos)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text(titulo).FontSize(13).Bold().FontColor(ColorPrimario);

            if (textos.Count == 0)
            {
                col.Item().Text("Sin registros.").FontSize(9).Italic().FontColor(ColorGrisTexto);
                return;
            }

            foreach (var t in textos.OrderBy(x => x.Orden))
            {
                if (t.Tipo == "titulo")
                    col.Item().PaddingTop(4).Text(t.Texto ?? "").FontSize(11).SemiBold().FontColor(ColorTitulo);
                else
                    col.Item().PaddingLeft(10).Row(r =>
                    {
                        r.ConstantItem(10).Text("•").FontSize(10).FontColor(ColorPrimario);
                        r.RelativeItem().Text(t.Texto ?? "").FontSize(10).LineHeight(1.4f);
                    });
            }
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // FORMA DE PAGO
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerFormasPago(IContainer container, PropuestaDetalleDto p)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text("Forma de Pago").FontSize(13).Bold().FontColor(ColorPrimario);

            if (p.FormasPago.Count == 0)
            {
                col.Item().Text("Sin forma de pago definida.").FontSize(9).Italic().FontColor(ColorGrisTexto);
                return;
            }

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(c =>
                {
                    c.ConstantColumn(60);
                    c.RelativeColumn();
                });

                foreach (var fp in p.FormasPago.OrderBy(x => x.Orden))
                {
                    table.Cell().Element(CeldaFila).Text($"{FormatearDecimal(fp.Porcentaje)} %").SemiBold();
                    table.Cell().Element(CeldaFila).Text(fp.CondicionLabel ?? fp.Condicion ?? "—");
                }
            });
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LISTADO DE EQUIPOS
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerTablaEquipos(IContainer container, List<PropuestaEquipoDto> equipos)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text("Listado de Equipos").FontSize(13).Bold().FontColor(ColorPrimario);

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(c =>
                {
                    c.ConstantColumn(25);
                    c.RelativeColumn(2); // Tipo / Subtipo
                    c.RelativeColumn(2); // Marca / Modelo
                    c.RelativeColumn(2); // N° Serie
                    c.RelativeColumn(2); // Códigos
                });

                table.Header(header =>
                {
                    header.Cell().Element(CeldaHeader).Text("#");
                    header.Cell().Element(CeldaHeader).Text("Tipo");
                    header.Cell().Element(CeldaHeader).Text("Marca / Modelo");
                    header.Cell().Element(CeldaHeader).Text("N° Serie");
                    header.Cell().Element(CeldaHeader).Text("Códigos");
                });

                int n = 0;
                foreach (var eq in equipos.OrderBy(x => x.Orden))
                {
                    n++;
                    table.Cell().Element(CeldaFila).Text(n.ToString());
                    table.Cell().Element(CeldaFila).Text($"{eq.Tipo ?? "—"}\n{eq.Subtipo ?? ""}").FontSize(8);
                    table.Cell().Element(CeldaFila).Text($"{eq.Marca ?? "—"}\n{eq.Modelo ?? ""}").FontSize(8);
                    table.Cell().Element(CeldaFila).Text(eq.NumSerie ?? "—").FontSize(8);
                    table.Cell().Element(CeldaFila).Text($"TW: {eq.CodigoTw ?? "—"}\nCli: {eq.CodigoCliente ?? "—"}").FontSize(8);
                }
            });
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // RESUMEN ECONÓMICO
    // ──────────────────────────────────────────────────────────────────────────
    // ──────────────────────────────────────────────────────────────────────────
    // CIERRE: Resumen Económico + Firma (van siempre juntos, nunca separados)
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerCierre(IContainer container, PropuestaDetalleDto p)
    {
        container.ShowEntire().Column(c =>
        {
            c.Spacing(14);
            c.Item().Element(x => ComponerResumenEconomico(x, p));
            c.Item().Element(x => ComponerFirma(x, p));
        });
    }

    private void ComponerResumenEconomico(IContainer container, PropuestaDetalleDto p)
    {
        // Full width: labels a la izquierda, montos a la derecha dentro del mismo bloque.
        container.Background(ColorFondoClaro).Padding(16).Column(col =>
        {
            col.Spacing(6);
            col.Item().PaddingBottom(4).Text("Resumen Económico")
                .FontSize(12).Bold().FontColor(ColorPrimario);

            FilaResumen(col, "Subtotal",      FormatearMoneda(p.Subtotal + p.DescuentoMonto, p.MonedaSimbolo));
            if (p.DescuentoMonto > 0)
                FilaResumen(col, p.DescuentoPct is > 0 ? $"Descuento ({FormatearDecimal(p.DescuentoPct.Value)}%)" : "Descuento",
                            $"- {FormatearMoneda(p.DescuentoMonto, p.MonedaSimbolo)}", ColorRojo);
            if (p.AplicaIgv)
                FilaResumen(col, $"IGV ({FormatearDecimal(p.IgvPct)}%)", FormatearMoneda(p.IgvMonto, p.MonedaSimbolo));

            col.Item().PaddingTop(8).BorderTop(1).BorderColor(ColorGrisBorde).PaddingTop(8).Row(r =>
            {
                r.RelativeItem().Text("TOTAL").FontSize(14).Bold().FontColor(ColorTitulo);
                r.AutoItem().Text(FormatearMoneda(p.Total, p.MonedaSimbolo))
                    .FontSize(16).Bold().FontColor(ColorVerde);
            });
        });
    }

    private static void FilaResumen(ColumnDescriptor col, string label, string valor, string color = "#0F172A")
    {
        col.Item().Row(r =>
        {
            r.RelativeItem().Text(label).FontSize(10).FontColor("#64748B");
            r.AutoItem().Text(valor).FontSize(11).SemiBold().FontColor(color);
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // FIRMA
    // ──────────────────────────────────────────────────────────────────────────
    private void ComponerFirma(IContainer container, PropuestaDetalleDto p)
    {
        container.PaddingTop(20).Row(r =>
        {
            r.RelativeItem().Column(c =>
            {
                c.Item().Height(50);
                c.Item().BorderTop(1).BorderColor(ColorTitulo).PaddingTop(4)
                    .Text(p.NombreResponsable ?? "Comercial Responsable").FontSize(10).SemiBold();
                c.Item().Text("Total Weight S.A.C.").FontSize(9).FontColor(ColorGrisTexto);
            });
            r.ConstantItem(40);
            r.RelativeItem().Column(c =>
            {
                c.Item().Height(50);
                c.Item().BorderTop(1).BorderColor(ColorTitulo).PaddingTop(4)
                    .Text(p.NombreContacto ?? "Cliente").FontSize(10).SemiBold();
                c.Item().Text(p.RazonSocial).FontSize(9).FontColor(ColorGrisTexto);
            });
        });
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ══════════════════════════════════════════════════════════════════════════
    private static List<PropuestaItemDto> ItemsPorSeccion(List<PropuestaItemDto> items, string seccion)
        => items.Where(i => (i.Seccion ?? "principal") == seccion).ToList();

    private static List<PropuestaTextoDto> TextosPorSeccion(List<PropuestaTextoDto> textos, string seccion)
        => textos.Where(t => t.Seccion == seccion).ToList();

    private static string FormatearMoneda(decimal valor, string? simbolo)
    {
        var s = string.IsNullOrEmpty(simbolo) ? "S/" : simbolo;
        return $"{s} {valor.ToString("N2", CulturaPe)}";
    }

    private static string FormatearDecimal(decimal valor)
        => valor.ToString("0.##", CulturaPe);

    private static string FormatearFecha(DateTime? fecha)
        => fecha?.ToString("dd/MM/yyyy", CulturaPe) ?? "—";
}
