using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// App Mobile HU-23 — PDF A4 de la CONSTANCIA DE RECEPCIÓN de instrumentos (QuestPDF): la OM, el cliente, la trazabilidad de entrega (guía, medio, quién entrega, quién recibe, fecha),
/// los instrumentos recibidos (estado físico, observaciones, accesorios y fotos), el motivo y los instrumentos pendientes si la recepción es parcial, y la firma de quien entrega dibujada
/// como VECTORES a partir de los trazos guardados (igual que la constancia de servicio de la HU-17). No es un certificado de calibración ni el informe técnico.
/// </summary>
public class GeneradorConstanciaRecepcionOmPdf : IGeneradorConstanciaRecepcionOmPdf
{
    private const string Primario = "#0057B8";
    private const string Titulo   = "#0F172A";
    private const string Gris     = "#64748B";
    private const string Borde    = "#E2E8F0";
    private const string Fondo    = "#EFF4FF";
    private const string Naranja  = "#B45309";

    private static string Texto(string? s) => string.IsNullOrWhiteSpace(s) ? "—" : s.Trim();

    private static string Nombre(string nombre, string? marca, string? modelo) =>
        string.Join(' ', new[] { nombre, marca, modelo }.Where(x => !string.IsNullOrWhiteSpace(x))).Trim();

    public byte[] Generar(ConstanciaRecepcionOmDto datos)
    {
        var c = datos.Cabecera;
        return Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(34);
                page.DefaultTextStyle(t => t.FontSize(9.5f).FontColor(Titulo));

                page.Header().Column(col =>
                {
                    col.Item().Row(r =>
                    {
                        r.RelativeItem().Column(t =>
                        {
                            t.Item().Text("CONSTANCIA DE RECEPCIÓN DE INSTRUMENTOS").FontSize(16).Bold().FontColor(Primario);
                            t.Item().Text($"Orden de metrología {c.NumeroOm}{(string.IsNullOrWhiteSpace(c.NumeroRq) ? "" : $" · RQ {c.NumeroRq}")}").FontColor(Gris);
                        });
                        r.ConstantItem(140).AlignRight().Column(t =>
                        {
                            t.Item().AlignRight().Text(CatalogoRecepcionOm.EtiquetaEstado(c.Estado).ToUpperInvariant()).Bold().FontSize(11).FontColor(c.Estado == "conforme" ? Primario : Naranja);
                            t.Item().AlignRight().Text("Constancia de recepción").FontSize(8).FontColor(Gris);
                        });
                    });
                    col.Item().PaddingTop(6).PaddingBottom(6).LineHorizontal(1).LineColor(Borde);
                });

                page.Content().Column(col =>
                {
                    col.Spacing(9);

                    col.Item().Column(d =>
                    {
                        d.Item().Text(Texto(c.Cliente)).FontSize(12).Bold();
                        if (!string.IsNullOrWhiteSpace(c.Direccion)) d.Item().Text(c.Direccion).FontColor(Gris);
                        if (!string.IsNullOrWhiteSpace(c.ContactoNombre)) d.Item().Text($"Contacto: {c.ContactoNombre}").FontColor(Gris);
                    });

                    col.Item().Column(s =>
                    {
                        s.Spacing(2);
                        s.Item().Text("Trazabilidad de entrega").Bold().FontSize(11).FontColor(Primario);
                        foreach (var (etiqueta, valor) in new[]
                        {
                            ("N° de guía", Texto(c.Guia)),
                            ("Medio de entrega", CatalogoRecepcionOm.EtiquetaMedio(c.Medio)),
                            ("Entregó", $"{Texto(c.Entrego)}{(string.IsNullOrWhiteSpace(c.EntregoCargo) ? "" : $" · {c.EntregoCargo}")}"),
                            ("Recibió", Texto(c.Recibio)),
                            ("Fecha y hora", $"{Texto(c.RecibidoEn)} (hora de Lima)"),
                        })
                            s.Item().Row(r =>
                            {
                                r.ConstantItem(110).Text(etiqueta).FontColor(Gris);
                                r.RelativeItem().Text(valor);
                            });
                    });

                    col.Item().Text($"Instrumentos recibidos ({datos.Instrumentos.Count})").Bold().FontSize(11).FontColor(Primario);
                    foreach (var i in datos.Instrumentos)
                    {
                        var accesorios = i.Accesorios.Count == 0 ? "Sin accesorios" : string.Join(", ", i.Accesorios.Select(CatalogoRecepcionOm.EtiquetaAccesorio));
                        col.Item().ShowEntire().Border(1).BorderColor(Borde).Padding(6).Column(f =>
                        {
                            f.Spacing(2);
                            f.Item().Row(r =>
                            {
                                r.RelativeItem().Text(Nombre(i.Nombre, i.Marca, i.Modelo)).Bold();
                                r.ConstantItem(90).AlignRight().Text(CatalogoRecepcionOm.EtiquetaEstado(i.EstadoFisico).ToUpperInvariant()).Bold().FontSize(8.5f)
                                    .FontColor(i.EstadoFisico == "observado" ? Naranja : Primario);
                            });
                            f.Item().Text($"N/S: {Texto(i.Serie)} · Código: {Texto(i.Codigo)}").FontColor(Gris).FontSize(8.5f);
                            f.Item().Text($"Observaciones: {Texto(i.Observaciones)}");
                            f.Item().Text($"Accesorios: {accesorios} · Fotos de recepción: {i.Fotos}").FontColor(Gris).FontSize(8.5f);
                        });
                    }

                    if (datos.Pendientes.Count > 0)
                        col.Item().ShowEntire().Background(Fondo).Border(1).BorderColor(Borde).Padding(8).Column(f =>
                        {
                            f.Spacing(2);
                            f.Item().Text($"Recepción parcial: faltan {datos.Pendientes.Count} instrumento{(datos.Pendientes.Count == 1 ? "" : "s")}").Bold().FontColor(Naranja);
                            if (!string.IsNullOrWhiteSpace(c.MotivoParcial)) f.Item().Text($"Motivo: {c.MotivoParcial}");
                            f.Item().Text("La orden queda abierta hasta recibirlos:").FontColor(Gris).FontSize(8.5f);
                            foreach (var p in datos.Pendientes)
                                f.Item().PaddingLeft(8).Text($"• {Nombre(p.Nombre, p.Marca, p.Modelo)} · N/S {Texto(p.Serie)}");
                        });

                    col.Item().PaddingTop(8).ShowEntire().Border(1).BorderColor(Borde).Padding(10).Column(f =>
                    {
                        f.Spacing(3);
                        f.Item().Text("Firma de quien entrega").Bold().FontSize(11).FontColor(Primario);
                        if (c.FirmaTrazos is not null) f.Item().Height(70).Svg(GeneradorConstanciaPdf.SvgFirma(c.FirmaTrazos));
                        else f.Item().Height(70).AlignMiddle().Text("Sin firma registrada.").FontColor(Gris);
                        f.Item().LineHorizontal(1).LineColor(Titulo);
                        f.Item().Text($"{Texto(c.Entrego)}{(string.IsNullOrWhiteSpace(c.EntregoCargo) ? "" : $" · {c.EntregoCargo}")}").Bold();
                        f.Item().Text($"{Texto(c.Cliente)} · {Texto(c.RecibidoEn)}").FontColor(Gris).FontSize(8.5f);
                    });
                });

                page.Footer().Row(r =>
                {
                    r.RelativeItem().Text("Constancia de recepción generada por la app de campo de Total Weight. La firma de quien entrega se conserva como trazos digitales. No es un certificado de calibración.")
                        .FontSize(7.5f).FontColor(Gris);
                    r.ConstantItem(60).AlignRight().Text(t =>
                    {
                        t.DefaultTextStyle(x => x.FontSize(7.5f).FontColor(Gris));
                        t.Span("Pág. ");
                        t.CurrentPageNumber();
                        t.Span(" / ");
                        t.TotalPages();
                    });
                });
            });
        }).GeneratePdf();
    }
}
