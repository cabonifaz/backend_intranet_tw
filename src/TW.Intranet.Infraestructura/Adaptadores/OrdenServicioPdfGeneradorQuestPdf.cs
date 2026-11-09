using System.Globalization;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// #4436 — PDF oficial de la Orden de Servicio / Metrología con QuestPDF (misma línea gráfica que el PDF de la propuesta).
/// Secciones: datos de la orden y del cliente · programación (técnico principal, apoyo, fecha y horario) · conceptos ·
/// equipos · observaciones · firmas. La OS no maneja montos. Una orden anulada lleva el aviso con su motivo.
/// </summary>
public class OrdenServicioPdfGeneradorQuestPdf : IOrdenServicioPdfGenerador
{
    private const string ColorPrimario    = "#2563EB";
    private const string ColorPrimarioOsc = "#1D4ED8";
    private const string ColorTitulo      = "#0F172A";
    private const string ColorSubtitulo   = "#475569";
    private const string ColorGrisTexto   = "#64748B";
    private const string ColorGrisBorde   = "#E2E8F0";
    private const string ColorFondoClaro  = "#F8FAFC";
    private const string ColorFondoTabla  = "#EFF4FF";
    private const string ColorRojo        = "#DC2626";
    private const string ColorFondoRojo   = "#FEF2F2";

    private static readonly CultureInfo CulturaPe = new("es-PE");

    public byte[] Generar(OrdenServicioPdfDto datos)
    {
        return Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(1.5f, Unit.Centimetre);
                page.DefaultTextStyle(x => x.FontSize(10).FontColor(ColorTitulo).FontFamily("Lato"));

                page.Header().Element(c => ComponerHeader(c, datos.Detalle));
                page.Content().Element(c => ComponerContenido(c, datos));
                page.Footer().Element(ComponerFooter);
            });
        }).GeneratePdf();
    }

    private static string TituloOrden(DetalleOrdenServicioDto d)
        => d.Tipo == "OM" ? "Orden de Metrología" : "Orden de Servicio";

    // ══════════════════════════════════════════════════════════════════════════
    // HEADER / FOOTER
    // ══════════════════════════════════════════════════════════════════════════
    private static void ComponerHeader(IContainer container, DetalleOrdenServicioDto d)
    {
        container.PaddingBottom(10).BorderBottom(1).BorderColor(ColorGrisBorde).Row(row =>
        {
            row.RelativeItem().Column(col =>
            {
                col.Item().Text("TOTAL WEIGHT").FontSize(14).Bold().FontColor(ColorPrimario);
                col.Item().Text(TituloOrden(d)).FontSize(9).FontColor(ColorGrisTexto);
            });
            row.ConstantItem(170).AlignRight().Column(col =>
            {
                col.Item().AlignRight().Text(d.Numero).FontSize(11).SemiBold().FontColor(ColorTitulo);
                col.Item().AlignRight().Text(d.EstadoLabel).FontSize(9).FontColor(ColorGrisTexto);
            });
        });
    }

    private static void ComponerFooter(IContainer container)
    {
        container.PaddingTop(10).BorderTop(1).BorderColor(ColorGrisBorde).Row(row =>
        {
            row.RelativeItem().Text(t =>
            {
                t.DefaultTextStyle(s => s.FontSize(8).FontColor(ColorGrisTexto));
                t.Span("Total Weight S.A.C.  ·  ");
                t.Span($"Generado el {DateTime.Now.ToString("dd/MM/yyyy HH:mm", CulturaPe)}");
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
    private static void ComponerContenido(IContainer container, OrdenServicioPdfDto datos)
    {
        var d = datos.Detalle;
        container.PaddingVertical(10).Column(col =>
        {
            col.Spacing(14);

            if (d.Estado == "anulada")
                col.Item().Element(c => ComponerAnulada(c, d));

            col.Item().Element(c => ComponerDatos(c, d));
            col.Item().Element(c => ComponerProgramacion(c, d, datos.Programacion));
            col.Item().Element(c => ComponerConceptos(c, datos.Conceptos));
            col.Item().Element(c => ComponerEquipos(c, datos.Equipos));

            if (!string.IsNullOrWhiteSpace(datos.Observaciones))
                col.Item().Column(c =>
                {
                    c.Item().PaddingBottom(6).Text("Observaciones").FontSize(13).Bold().FontColor(ColorPrimario);
                    c.Item().Text(datos.Observaciones!).FontSize(10).LineHeight(1.4f);
                });

            col.Item().Element(c => ComponerFirmas(c, d, datos.Programacion));
        });
    }

    private static void ComponerAnulada(IContainer container, DetalleOrdenServicioDto d)
    {
        container.Background(ColorFondoRojo).Border(1).BorderColor(ColorRojo).Padding(10).Column(c =>
        {
            c.Item().Text($"{TituloOrden(d).ToUpperInvariant()} ANULADA").FontSize(11).Bold().FontColor(ColorRojo);
            var detalle = string.Join(" · ", new[]
            {
                d.MotivoAnulacion,
                d.AnuladoEn is { } f ? $"el {FormatearFecha(f)}" : null,
                string.IsNullOrWhiteSpace(d.AnuladoPor) ? null : $"por {d.AnuladoPor}",
            }.Where(x => !string.IsNullOrWhiteSpace(x)));
            if (detalle.Length > 0) c.Item().Text(detalle).FontSize(9).FontColor(ColorRojo);
            if (!string.IsNullOrWhiteSpace(d.ComentarioAnulacion))
                c.Item().Text(d.ComentarioAnulacion!).FontSize(9).FontColor(ColorSubtitulo);
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // DATOS DE LA ORDEN Y DEL CLIENTE
    // ──────────────────────────────────────────────────────────────────────────
    private static void ComponerDatos(IContainer container, DetalleOrdenServicioDto d)
    {
        container.ShowEntire().Background(ColorFondoClaro).Padding(15).Column(col =>
        {
            col.Spacing(8);
            col.Item().Text($"{TituloOrden(d)}  ·  {d.Numero}").FontSize(18).Bold().FontColor(ColorPrimario);
            col.Item().PaddingTop(4).Row(row =>
            {
                row.RelativeItem().Column(c =>
                {
                    c.Item().Text("CLIENTE").FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
                    c.Item().Text(d.RazonSocial ?? "—").FontSize(12).SemiBold();
                    if (!string.IsNullOrWhiteSpace(d.Ruc))
                        c.Item().Text($"RUC: {d.Ruc}").FontSize(9).FontColor(ColorSubtitulo);
                    if (!string.IsNullOrWhiteSpace(d.DireccionOperaciones))
                    {
                        c.Item().PaddingTop(6).Text("DIRECCIÓN DE OPERACIONES").FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
                        c.Item().Text(d.DireccionOperaciones!).FontSize(10);
                    }
                    if (!string.IsNullOrWhiteSpace(d.Contacto))
                    {
                        c.Item().PaddingTop(6).Text("CONTACTO").FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
                        c.Item().Text(d.Contacto!).FontSize(10);
                        var linea = string.Join(" · ", new[] { d.CargoContacto, d.TelefonoContacto, d.CorreoContacto }
                                                         .Where(x => !string.IsNullOrWhiteSpace(x)));
                        if (linea.Length > 0) c.Item().Text(linea).FontSize(9).FontColor(ColorGrisTexto);
                    }
                });
                row.ConstantItem(190).Column(c =>
                {
                    FilaDato(c, "PROPUESTA", d.NumeroPropuesta ?? "—");   // PC-0012-1-2026 ya incluye la versión
                    FilaDato(c, "REQUERIMIENTO", d.NumeroRq ?? "—");
                    FilaDato(c, "RESPONSABLE COMERCIAL", d.Responsable ?? "—");
                    FilaDato(c, "FECHA DE EMISIÓN", FormatearFecha(d.FechaEmision ?? d.FechaDocumento));
                    if (d.Tipo != "OM" && (d.FechaProgramadaDesde is not null || d.FechaProgramadaHasta is not null))
                        FilaDato(c, "FECHA TENTATIVA",
                            d.FechaProgramadaHasta is null || d.FechaProgramadaHasta == d.FechaProgramadaDesde
                                ? FormatearFecha(d.FechaProgramadaDesde)
                                : $"{FormatearFecha(d.FechaProgramadaDesde)} al {FormatearFecha(d.FechaProgramadaHasta)}");
                });
            });
        });
    }

    private static void FilaDato(ColumnDescriptor col, string label, string valor)
    {
        col.Item().PaddingBottom(4).Column(c =>
        {
            c.Item().Text(label).FontSize(8).FontColor(ColorGrisTexto).LetterSpacing(0.5f);
            c.Item().Text(valor).FontSize(10).SemiBold();
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // PROGRAMACIÓN
    // ──────────────────────────────────────────────────────────────────────────
    private static void ComponerProgramacion(IContainer container, DetalleOrdenServicioDto d, ProgramacionOrdenServicioDto? p)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text("Programación").FontSize(13).Bold().FontColor(ColorPrimario);

            if (p is null || !p.TieneProgramacion)
            {
                col.Item().Text($"La {TituloOrden(d).ToLowerInvariant()} aún no ha sido programada.")
                    .FontSize(9).Italic().FontColor(ColorGrisTexto);
                return;
            }

            var apoyo = p.Personal
                .Where(x => x.IdUsuario != p.IdTecnico && !string.Equals(x.Rol, "principal", StringComparison.OrdinalIgnoreCase))
                .Select(x => x.Nombre)
                .ToList();
            var horario = string.IsNullOrWhiteSpace(p.HoraInicio) ? "—"
                : string.IsNullOrWhiteSpace(p.HoraFinEstimada) ? p.HoraInicio! : $"{p.HoraInicio} – {p.HoraFinEstimada}";

            col.Item().Border(1).BorderColor(ColorGrisBorde).Padding(10).Row(row =>
            {
                row.RelativeItem().Column(c =>
                {
                    FilaDato(c, "TÉCNICO PRINCIPAL", p.Tecnico ?? "—");
                    FilaDato(c, "PERSONAL DE APOYO", apoyo.Count == 0 ? "—" : string.Join(", ", apoyo));
                });
                row.RelativeItem().Column(c =>
                {
                    FilaDato(c, "FECHA PROGRAMADA", FormatearFecha(p.FechaEjecucion));
                    FilaDato(c, "HORARIO", horario);
                });
                row.RelativeItem().Column(c =>
                {
                    FilaDato(c, "CONFIRMACIÓN DEL CLIENTE", p.ConfirmacionCliente ? "Confirmada" : "Pendiente");
                    if (!string.IsNullOrWhiteSpace(p.HoraLlegadaReal) || !string.IsNullOrWhiteSpace(p.HoraFinReal))
                        FilaDato(c, "EJECUCIÓN REAL", $"{p.HoraLlegadaReal ?? "—"} – {p.HoraFinReal ?? "—"}");
                });
            });

            if (!string.IsNullOrWhiteSpace(p.NotasOperativas))
                col.Item().PaddingTop(6).Text(t =>
                {
                    t.Span("Notas operativas: ").SemiBold().FontSize(9);
                    t.Span(p.NotasOperativas!).FontSize(9);
                });
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CONCEPTOS
    // ──────────────────────────────────────────────────────────────────────────
    private static void ComponerConceptos(IContainer container, List<ConceptoOrdenServicioDto> conceptos)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text("Conceptos del servicio").FontSize(13).Bold().FontColor(ColorPrimario);
            if (conceptos.Count == 0)
            {
                col.Item().Text("No hay conceptos registrados.").FontSize(9).Italic().FontColor(ColorGrisTexto);
                return;
            }

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(c =>
                {
                    c.ConstantColumn(22);   // #
                    c.ConstantColumn(60);   // Código
                    c.RelativeColumn(4);    // Descripción + alcance
                    c.RelativeColumn(2);    // Aplica a
                });
                table.Header(h =>
                {
                    h.Cell().Element(CeldaHeader).Text("#");
                    h.Cell().Element(CeldaHeader).Text("Código");
                    h.Cell().Element(CeldaHeader).Text("Descripción");
                    h.Cell().Element(CeldaHeader).Text("Aplica a");
                });

                int n = 0;
                foreach (var c in conceptos)
                {
                    n++;
                    table.Cell().Element(CeldaFila).Text(n.ToString());
                    table.Cell().Element(CeldaFila).Text(c.Codigo ?? "—");
                    table.Cell().Element(CeldaFila).Column(x =>
                    {
                        x.Item().Text(c.Descripcion).FontSize(9);
                        if (!string.IsNullOrWhiteSpace(c.Alcance))
                            x.Item().Text($"Alcance: {c.Alcance}").FontSize(8).FontColor(ColorGrisTexto);
                    });
                    table.Cell().Element(CeldaFila).Text(c.General ? "General" : string.Join(", ", c.EquiposAplicados));
                }
            });
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // EQUIPOS
    // ──────────────────────────────────────────────────────────────────────────
    private static void ComponerEquipos(IContainer container, List<EquipoOrdenServicioDto> equipos)
    {
        container.Column(col =>
        {
            col.Item().PaddingBottom(6).Text($"Equipos ({equipos.Count})").FontSize(13).Bold().FontColor(ColorPrimario);
            if (equipos.Count == 0)
            {
                col.Item().Text("No hay equipos registrados.").FontSize(9).Italic().FontColor(ColorGrisTexto);
                return;
            }

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(c =>
                {
                    c.ConstantColumn(22);   // #
                    c.ConstantColumn(62);   // Código TW
                    c.ConstantColumn(62);   // Clasificación
                    c.RelativeColumn(3);    // Marca / Modelo
                    c.RelativeColumn(2);    // N° serie
                    c.RelativeColumn(2);    // Alcance
                    c.RelativeColumn(2);    // Ubicación
                    c.ConstantColumn(58);   // Estado
                });
                table.Header(h =>
                {
                    h.Cell().Element(CeldaHeader).Text("#");
                    h.Cell().Element(CeldaHeader).Text("Código TW");
                    h.Cell().Element(CeldaHeader).Text("Tipo");
                    h.Cell().Element(CeldaHeader).Text("Marca / Modelo");
                    h.Cell().Element(CeldaHeader).Text("N° serie");
                    h.Cell().Element(CeldaHeader).Text("Alcance");
                    h.Cell().Element(CeldaHeader).Text("Ubicación");
                    h.Cell().Element(CeldaHeader).Text("Estado");
                });

                int n = 0;
                foreach (var e in equipos)
                {
                    n++;
                    table.Cell().Element(CeldaFila).Text(n.ToString());
                    table.Cell().Element(CeldaFila).Text(e.CodigoTw);
                    table.Cell().Element(CeldaFila).Text(Valor(e.ClasificacionLabel));
                    table.Cell().Element(CeldaFila).Text(Valor($"{e.Marca} {e.Modelo}".Trim()));
                    table.Cell().Element(CeldaFila).Text(Valor(e.NumSerie));
                    table.Cell().Element(CeldaFila).Text(Valor(e.Alcance));
                    table.Cell().Element(CeldaFila).Text(Valor(e.Ubicacion ?? e.Sede));
                    table.Cell().Element(CeldaFila).Text(EstadoEquipo(e.EstadoEjecucion));
                }
            });
        });
    }

    // ──────────────────────────────────────────────────────────────────────────
    // FIRMAS
    // ──────────────────────────────────────────────────────────────────────────
    private static void ComponerFirmas(IContainer container, DetalleOrdenServicioDto d, ProgramacionOrdenServicioDto? p)
    {
        container.ShowEntire().PaddingTop(25).Row(r =>
        {
            r.RelativeItem().Column(c =>
            {
                c.Item().Height(45);
                c.Item().BorderTop(1).BorderColor(ColorTitulo).PaddingTop(4)
                    .Text(p?.Tecnico ?? d.Responsable ?? "Total Weight").FontSize(10).SemiBold();
                c.Item().Text(p?.Tecnico is null ? "Responsable · Total Weight S.A.C." : "Técnico responsable · Total Weight S.A.C.")
                    .FontSize(9).FontColor(ColorGrisTexto);
            });
            r.ConstantItem(40);
            r.RelativeItem().Column(c =>
            {
                c.Item().Height(45);
                c.Item().BorderTop(1).BorderColor(ColorTitulo).PaddingTop(4)
                    .Text(d.Contacto ?? "Cliente").FontSize(10).SemiBold();
                c.Item().Text($"Conformidad del cliente · {d.RazonSocial ?? ""}".TrimEnd(' ', '·'))
                    .FontSize(9).FontColor(ColorGrisTexto);
            });
        });
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Helpers
    // ══════════════════════════════════════════════════════════════════════════
    private static IContainer CeldaHeader(IContainer c)
        => c.Background(ColorFondoTabla).Padding(5).DefaultTextStyle(s => s.FontSize(8).SemiBold().FontColor(ColorPrimarioOsc));

    private static IContainer CeldaFila(IContainer c)
        => c.BorderBottom(1).BorderColor(ColorGrisBorde).Padding(5).DefaultTextStyle(s => s.FontSize(8));

    private static string Valor(string? v) => string.IsNullOrWhiteSpace(v) ? "—" : v!;

    private static string EstadoEquipo(string? estado) => estado switch
    {
        "pendiente"  => "Pendiente",
        "en_proceso" => "En proceso",
        "ejecutado"  => "Ejecutado",
        "observado"  => "Observado",
        null or ""   => "—",
        _            => estado,
    };

    private static string FormatearFecha(DateTime? fecha)
        => fecha?.ToString("dd/MM/yyyy", CulturaPe) ?? "—";
}
