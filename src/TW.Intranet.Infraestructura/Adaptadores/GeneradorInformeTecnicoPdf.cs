using System.Globalization;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Revisión Técnica — PDF A4 del INFORME TÉCNICO del servicio (QuestPDF), con lo que registró el técnico desde la app: cliente y servicio,
/// equipo, quién atendió en planta, detalle del servicio, procedimiento, ensayos y resultado global, fallas / observaciones, recomendaciones,
/// diagnóstico final y registro fotográfico. Se genera en el momento (no hay plantilla oficial: mismo estilo del pre-informe y del complementario).
/// </summary>
public class GeneradorInformeTecnicoPdf : IGeneradorInformeTecnicoPdf
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
    private static string SiNo(bool v) => v ? "Sí" : "No";

    private static string Nivel(string? n) => n switch
    {
        "critico" => "Crítico", "alto" => "Alto", "medio" => "Medio", "bajo" => "Bajo", _ => "—",
    };

    private static string Prioridad(string? p) => p switch
    {
        "alta" => "Alta", "media" => "Media", "baja" => "Baja", _ => Texto(p),
    };

    public byte[] Generar(DatosInformeTecnicoPdf datos)
    {
        var d = datos.Detalle;
        var c = d.Cabecera;
        var numero = !string.IsNullOrWhiteSpace(c.NumeroInformeTecnico) ? c.NumeroInformeTecnico : c.NumeroInforme;

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
                            t.Item().Text("INFORME TÉCNICO").FontSize(18).Bold().FontColor(Primario);
                            t.Item().Text($"{Texto(c.TipoOs)} {Texto(c.NumeroOs)}{(string.IsNullOrWhiteSpace(c.NumeroRq) ? "" : $" · RQ {c.NumeroRq}")}").FontColor(Gris);
                        });
                        r.ConstantItem(170).AlignRight().Column(t =>
                        {
                            t.Item().AlignRight().Text($"Informe N° {Texto(numero)}").Bold();
                            t.Item().AlignRight().Text($"Estado: {Texto(c.EstadoLabel)}").FontSize(8).FontColor(Gris);
                            if (c.Via == "intranet")
                                t.Item().AlignRight().Text($"Registrado desde la intranet por {Texto(c.RegistradoPor)}").FontSize(7.5f).FontColor(Gris);
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
                        ("Tipo de servicio", Texto(c.TipoServicio)),
                        ("Fecha de ejecución", $"{Fecha(c.FechaEjecucion)} · {Texto(c.HoraInicio)} a {Texto(c.HoraFin)}"),
                        ("Técnico", Texto(c.Tecnico)),
                        ("Atendió en planta", d.ResponsableCliente is { } rc
                            ? $"{Texto(rc.Nombre)}{(string.IsNullOrWhiteSpace(rc.Cargo) ? "" : $" · {rc.Cargo}")}{(string.IsNullOrWhiteSpace(rc.Telefono) ? "" : $" · {rc.Telefono}")}"
                            : Texto(c.Contacto)),
                    });

                    Seccion(col, "Equipo", new[]
                    {
                        ("Equipo", Texto(c.Equipo)),
                        ("Marca · modelo", $"{Texto(c.Marca)} · {Texto(c.Modelo)}"),
                        ("Serie · código TW", $"{Texto(c.NumeroSerie)} · {Texto(c.CodigoTw)}"),
                        ("Tipo", Texto(c.TipoEquipo)),
                    });

                    // Detalle del servicio y procedimiento
                    col.Item().Column(s =>
                    {
                        s.Spacing(3);
                        s.Item().Text("Detalle del servicio").Bold().FontSize(11).FontColor(Primario);
                        if (d.DetalleServicio is { } ds)
                        {
                            s.Item().Text($"Tipo de equipo: {Texto(ds.TipoEquipo)} · Anillos de fijación: {(ds.AnillosFijacion is { } a ? SiNo(a) : "—")}");
                            if (ds.Celdas.Count > 0) s.Item().Text($"Celdas (mV): {string.Join(" · ", ds.Celdas.Select(x => Num(x)))}");
                            s.Item().Text($"Pruebas por sumatoria hasta: {Num(ds.SumatoriaHasta)} · por comparación hasta: {Num(ds.ComparacionHasta)}");
                        }
                        var hechos = d.Procedimiento.Where(p => p.Realizado).OrderBy(p => p.Orden).ToList();
                        s.Item().Text(hechos.Count == 0 ? "Trabajos realizados: —" : "Trabajos realizados:");
                        foreach (var h in hechos) s.Item().PaddingLeft(10).Text($"• {Texto(h.Titulo)}{(string.IsNullOrWhiteSpace(h.Nota) ? "" : $" — {h.Nota}")}");
                    });

                    // Ensayos y resultado global
                    col.Item().Column(s =>
                    {
                        s.Spacing(4);
                        s.Item().Text("Ensayos y calibración").Bold().FontSize(11).FontColor(Primario);
                        s.Item().Text(t =>
                        {
                            t.Span("Resultado global: ");
                            var dentro = c.ResultadoGlobal == "dentro";
                            t.Span(c.ResultadoGlobal is null ? "—" : dentro ? "Dentro de tolerancia" : "Fuera de tolerancia")
                             .Bold().FontColor(c.ResultadoGlobal is null ? Titulo : dentro ? Verde : Rojo);
                            t.Span($" · Error máximo: {Num(c.ErrorMaximo)}");
                        });
                        if (!string.IsNullOrWhiteSpace(c.ErrorCritico)) s.Item().Text($"Guardado con error crítico. Motivo: {c.ErrorCritico}").FontColor(Rojo);
                        TablaEnsayos(s, "Pesaje", d.Ensayos.Where(e => e.Tipo == "pesaje").ToList());
                        TablaEnsayos(s, "Excentricidad", d.Ensayos.Where(e => e.Tipo == "excentricidad").ToList());
                        if (d.Ensayos.Count == 0) s.Item().Text("Sin lecturas registradas.").FontColor(Gris);
                        if (!string.IsNullOrWhiteSpace(d.ComentarioPruebas)) s.Item().Text($"Comentario: {d.ComentarioPruebas}");
                    });

                    // Fallas / observaciones
                    col.Item().Column(s =>
                    {
                        s.Spacing(4);
                        s.Item().Text("Fallas y observaciones").Bold().FontSize(11).FontColor(Primario);
                        if (d.Observaciones.Count == 0) s.Item().Text("Sin fallas ni observaciones.").FontColor(Gris);
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
                                $"• {Texto(r.Titulo)} — Prioridad {Prioridad(r.Prioridad)}" +
                                $"{(string.IsNullOrWhiteSpace(r.Plazo) ? "" : $" · Plazo: {r.Plazo}")}" +
                                $"{(string.IsNullOrWhiteSpace(r.Descripcion) ? "" : $". {r.Descripcion}")}");
                    });

                    // Diagnóstico final
                    if (d.DiagnosticoFinal is { } dg)
                        Seccion(col, "Diagnóstico final", new[]
                        {
                            ("Severidad general", GeneradorPreInformePdf.Severidad(dg.SeveridadGeneral)),
                            ("Estado del equipo", GeneradorPreInformePdf.EstadoEquipo(dg.EstadoEquipo)),
                            ("Revisión de Jefatura", SiNo(dg.RevisionJefatura)),
                            ("Precotización", SiNo(dg.Precotizacion)),
                            ("Segunda visita", SiNo(dg.SegundaVisita)),
                            ("Aplica garantía", SiNo(dg.AplicaGarantia)),
                        });
                    if (!string.IsNullOrWhiteSpace(c.Diagnostico))
                        col.Item().Text($"Resumen del diagnóstico: {c.Diagnostico.Trim()}");

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
                                        fc.Item().Text($"{Texto(f.MomentoLabel)}{(f.Forzada ? " · aceptada por el técnico" : "")}").FontSize(7.5f).FontColor(Gris);
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
                    r.RelativeItem().Text($"Informe técnico generado el {datos.GeneradoEn:dd/MM/yyyy HH:mm} (hora de Lima) por la intranet de Total Weight " +
                                          "con los datos registrados por el técnico.").FontSize(7.5f).FontColor(Gris);
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

    private static void TablaEnsayos(ColumnDescriptor s, string titulo, List<EnsayoInformeDto> filas)
    {
        if (filas.Count == 0) return;
        s.Item().Text(titulo).Bold().FontSize(9);
        s.Item().Table(t =>
        {
            t.ColumnsDefinition(cd => { cd.RelativeColumn(2); cd.RelativeColumn(); cd.RelativeColumn(); cd.RelativeColumn(); cd.RelativeColumn(); cd.RelativeColumn(1.4f); });
            foreach (var h in new[] { "Punto", "Carga", "Lectura", "Error", "EMP", "Resultado" })
                t.Cell().Background(Fondo).BorderBottom(1).BorderColor(Borde).Padding(3).Text(h).Bold().FontSize(8);
            foreach (var e in filas)
            {
                t.Cell().Padding(3).Text(Texto(e.Punto)).FontSize(8.5f);
                t.Cell().Padding(3).Text(Num(e.Carga)).FontSize(8.5f);
                t.Cell().Padding(3).Text(Num(e.Lectura)).FontSize(8.5f);
                t.Cell().Padding(3).Text(Num(e.Error)).FontSize(8.5f);
                t.Cell().Padding(3).Text(e.Tolerancia is null ? "—" : $"±{Num(e.Tolerancia)}").FontSize(8.5f);
                t.Cell().Padding(3).Text(Texto(e.ResultadoLabel)).FontSize(8.5f).FontColor(e.Resultado == "no_conforme" ? Rojo : Titulo);
            }
        });
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
