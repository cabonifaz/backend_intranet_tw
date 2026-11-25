using System.Globalization;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Revisión Técnica — PDF A4 del INFORME COMPLEMENTARIO (QuestPDF). Documento del Supervisor Técnico que acompaña al informe del técnico
/// (que es inmutable): datos del servicio, resultado de los ensayos del técnico (solo lectura), observaciones generales, observaciones,
/// recomendaciones, registro fotográfico y precotización. Se genera en el momento con los datos vigentes.
/// </summary>
public class GeneradorInformeComplementarioPdf : IGeneradorInformeComplementarioPdf
{
    private const string Primario = "#0057B8";
    private const string Titulo   = "#0F172A";
    private const string Gris     = "#64748B";
    private const string Borde    = "#E2E8F0";
    private const string Fondo    = "#EFF4FF";
    private const string Rojo     = "#B91C1C";
    private const string Verde    = "#15803D";

    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    private static string Num(decimal? n) => n is null ? "—" : n.Value.ToString("0.####", Inv);
    private static string Texto(string? s) => string.IsNullOrWhiteSpace(s) ? "—" : s.Trim();
    private static string Fecha(DateTime? f) => f is null ? "—" : f.Value.ToString("dd/MM/yyyy", Inv);

    private static string Nivel(string? n) => n switch
    {
        "critico" => "Crítico", "alto" => "Alto", "medio" => "Medio", "bajo" => "Bajo", _ => "—",
    };

    private static string Prioridad(string? p) => p switch
    {
        "alta" => "Alta", "media" => "Media", "baja" => "Baja", "opcional" => "Opcional", _ => Texto(p),
    };

    public byte[] Generar(DatosInformeComplementarioPdf datos)
    {
        var d = datos.Detalle;
        var c = d.Cabecera;

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
                            t.Item().Text("INFORME COMPLEMENTARIO").FontSize(18).Bold().FontColor(Primario);
                            t.Item().Text($"{Texto(c.TipoOs)} {Texto(c.NumeroOs)}{(string.IsNullOrWhiteSpace(c.NumeroRq) ? "" : $" · RQ {c.NumeroRq}")}").FontColor(Gris);
                        });
                        r.ConstantItem(170).AlignRight().Column(t =>
                        {
                            t.Item().AlignRight().Text($"N° {Texto(c.NumeroComplementario)}").Bold();
                            t.Item().AlignRight().Text($"Complementa al informe {Texto(c.NumeroInformeOriginal)}").FontSize(8).FontColor(Gris);
                            if (c.Estado == "borrador")
                                t.Item().AlignRight().Text("BORRADOR (sin guardar)").Bold().FontSize(8.5f).FontColor(Rojo);
                        });
                    });
                    col.Item().PaddingTop(6).PaddingBottom(6).LineHorizontal(1).LineColor(Borde);
                });

                page.Content().Column(col =>
                {
                    col.Spacing(9);

                    Seccion(col, "Cliente y servicio", new[]
                    {
                        ("Empresa", $"{Texto(c.RazonSocial)}{(string.IsNullOrWhiteSpace(c.Ruc) ? "" : $" · RUC {c.Ruc}")}"),
                        ("Sede", Texto(c.Sede)),
                        ("Contacto", Texto(c.Contacto)),
                        ("Tipo de servicio", Texto(c.TipoServicio)),
                        ("Fecha de ejecución", $"{Fecha(c.FechaEjecucion)} · {Texto(c.HoraInicio)} a {Texto(c.HoraFin)}"),
                        ("Técnico", Texto(c.Tecnico)),
                        ("Supervisor", Texto(c.Supervisor)),
                    });

                    Seccion(col, "Equipo", new[]
                    {
                        ("Equipo", Texto(c.Equipo)),
                        ("Marca · modelo", $"{Texto(c.Marca)} · {Texto(c.Modelo)}"),
                        ("Serie · código TW", $"{Texto(c.NumeroSerie)} · {Texto(c.CodigoTw)}"),
                        ("Tipo", Texto(c.TipoEquipo)),
                    });

                    // Resultado de los ensayos del técnico (solo lectura)
                    col.Item().Column(s =>
                    {
                        s.Spacing(3);
                        s.Item().Text("Resultado de los ensayos (informe del técnico)").Bold().FontSize(11).FontColor(Primario);
                        s.Item().Text(t =>
                        {
                            t.Span("Resultado global: ");
                            var dentro = c.ResultadoGlobal == "dentro";
                            t.Span(c.ResultadoGlobal is null ? "—" : dentro ? "Dentro de tolerancia" : "Fuera de tolerancia")
                             .Bold().FontColor(c.ResultadoGlobal is null ? Titulo : dentro ? Verde : Rojo);
                            t.Span($" · Error máximo: {Num(c.ErrorMaximo)}{(string.IsNullOrWhiteSpace(c.ErrorMaximoDetalle) ? "" : $" ({c.ErrorMaximoDetalle})")}");
                        });
                        if (!string.IsNullOrWhiteSpace(c.Diagnostico)) s.Item().Text($"Diagnóstico: {c.Diagnostico}");
                        var pesaje = d.Ensayos.Where(e => e.Tipo == "pesaje").ToList();
                        var exc = d.Ensayos.Where(e => e.Tipo == "excentricidad").ToList();
                        if (pesaje.Count > 0) s.Item().Text($"Pesaje: {pesaje.Count} puntos · {pesaje.Count(e => e.Resultado == "no_conforme")} fuera de tolerancia").FontColor(Gris);
                        if (exc.Count > 0) s.Item().Text($"Excentricidad: {exc.Count} posiciones · {exc.Count(e => e.Resultado == "no_conforme")} no conformes").FontColor(Gris);
                    });

                    // Observaciones generales del supervisor
                    if (!string.IsNullOrWhiteSpace(c.ObservacionesGenerales))
                        col.Item().Column(s =>
                        {
                            s.Spacing(3);
                            s.Item().Text("Observaciones generales del supervisor").Bold().FontSize(11).FontColor(Primario);
                            s.Item().Text(c.ObservacionesGenerales.Trim());
                        });

                    // Observaciones
                    col.Item().Column(s =>
                    {
                        s.Spacing(4);
                        s.Item().Text("Observaciones").Bold().FontSize(11).FontColor(Primario);
                        if (d.Observaciones.Count == 0) s.Item().Text("Sin observaciones.").FontColor(Gris);
                        foreach (var o in d.Observaciones)
                            s.Item().Border(1).BorderColor(Borde).Padding(6).Column(oc =>
                            {
                                oc.Spacing(2);
                                oc.Item().Text($"{Texto(o.Codigo)} · {Texto(o.Titulo)} — Afectación {Nivel(o.NivelAfectacion)}").Bold();
                                if (!string.IsNullOrWhiteSpace(o.Descripcion)) oc.Item().Text(o.Descripcion.Trim());
                                if (!string.IsNullOrWhiteSpace(o.Ubicacion)) oc.Item().Text($"Ubicación: {o.Ubicacion}").FontColor(Gris).FontSize(8.5f);
                            });
                    });

                    // Recomendaciones
                    col.Item().Column(s =>
                    {
                        s.Spacing(3);
                        s.Item().Text("Recomendaciones").Bold().FontSize(11).FontColor(Primario);
                        if (d.Recomendaciones.Count == 0) s.Item().Text("Sin recomendaciones.").FontColor(Gris);
                        foreach (var r in d.Recomendaciones)
                            s.Item().PaddingLeft(6).Text(
                                $"• {Texto(r.Codigo)} {Texto(r.Titulo)} — Prioridad {Prioridad(r.Prioridad)}" +
                                $"{(string.IsNullOrWhiteSpace(r.Plazo) ? "" : $" · Plazo: {r.Plazo}")}" +
                                $"{(string.IsNullOrWhiteSpace(r.Descripcion) ? "" : $". {r.Descripcion}")}" +
                                $"{(string.IsNullOrWhiteSpace(r.CodigoObservacion) ? "" : $" (ref. {r.CodigoObservacion})")}");
                    });

                    // Precotización
                    if (d.Precotizacion.Count > 0)
                        col.Item().Column(s =>
                        {
                            s.Spacing(4);
                            s.Item().Text($"Precotización {Texto(c.NumeroPrecot)}").Bold().FontSize(11).FontColor(Primario);
                            if (!string.IsNullOrWhiteSpace(c.NotaPrecotizacion)) s.Item().Text($"Nota para Comercial: {c.NotaPrecotizacion}").FontColor(Gris);
                            s.Item().Table(t =>
                            {
                                t.ColumnsDefinition(cd => { cd.ConstantColumn(24); cd.RelativeColumn(4); cd.RelativeColumn(2); cd.RelativeColumn(1.4f); cd.RelativeColumn(1.4f); });
                                foreach (var h in new[] { "N°", "Concepto", "Código", "Cantidad", "Prioridad" })
                                    t.Cell().Background(Fondo).BorderBottom(1).BorderColor(Borde).Padding(3).Text(h).Bold().FontSize(8);
                                var n = 0;
                                foreach (var i in d.Precotizacion)
                                {
                                    n++;
                                    t.Cell().Padding(3).Text(n.ToString(Inv)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text($"{Texto(i.Concepto)}{(string.IsNullOrWhiteSpace(i.DescripcionTecnica) ? "" : $" — {i.DescripcionTecnica}")}").FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Texto(i.Codigo)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text($"{Num(i.Cantidad)} {Texto(i.Unidad)}").FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Prioridad(i.Prioridad)).FontSize(8.5f);
                                }
                            });
                        });

                    // Registro fotográfico
                    col.Item().Column(s =>
                    {
                        s.Spacing(5);
                        s.Item().Text($"Registro fotográfico ({d.Fotos.Count})").Bold().FontSize(11).FontColor(Primario);
                        if (d.Fotos.Count == 0) s.Item().Text("Sin fotos.").FontColor(Gris);
                        var conImagen = d.Fotos.Where(f => datos.Imagenes.ContainsKey(f.IdEvidencia)).ToList();
                        foreach (var fila in conImagen.Chunk(3))
                            s.Item().Row(r =>
                            {
                                r.Spacing(6);
                                foreach (var f in fila)
                                    r.RelativeItem().Border(1).BorderColor(Borde).Padding(4).Column(fc =>
                                    {
                                        fc.Spacing(2);
                                        fc.Item().Height(130).AlignCenter().Image(datos.Imagenes[f.IdEvidencia]).FitArea();
                                        fc.Item().Text($"{Texto(f.MomentoLabel)}{(f.Copiada ? "" : " · agregada por el supervisor")}").FontSize(7.5f).FontColor(Gris);
                                        if (!string.IsNullOrWhiteSpace(f.Descripcion)) fc.Item().Text(f.Descripcion.Trim()).FontSize(7.5f);
                                    });
                                for (var k = fila.Length; k < 3; k++) r.RelativeItem();
                            });
                        var sinImagen = d.Fotos.Count - conImagen.Count;
                        if (sinImagen > 0)
                            s.Item().Text($"{sinImagen} {(sinImagen == 1 ? "archivo" : "archivos")} (videos o fotos no incluidas) se pueden ver en la intranet.").FontSize(8).FontColor(Gris);
                    });
                });

                page.Footer().Row(r =>
                {
                    r.RelativeItem().Text($"Informe complementario generado el {datos.GeneradoEn:dd/MM/yyyy HH:mm} (hora de Lima) por la intranet de Total Weight. " +
                                          "Complementa al informe técnico del servicio; no lo reemplaza.").FontSize(7.5f).FontColor(Gris);
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

    /// <summary>Un bloque con título y filas "etiqueta: valor".</summary>
    private static void Seccion(ColumnDescriptor col, string titulo, IEnumerable<(string Etiqueta, string Valor)> filas)
    {
        col.Item().Column(s =>
        {
            s.Spacing(2);
            s.Item().Text(titulo).Bold().FontSize(11).FontColor(Primario);
            foreach (var (etiqueta, valor) in filas)
                s.Item().Row(r =>
                {
                    r.ConstantItem(120).Text(etiqueta).FontColor(Gris);
                    r.RelativeItem().Text(valor);
                });
        });
    }
}
