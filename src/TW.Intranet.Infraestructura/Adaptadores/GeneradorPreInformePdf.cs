using System.Globalization;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// App Mobile — PDF A4 del PRE-INFORME (QuestPDF): la cabecera del informe del equipo (datos, equipo, detalle del servicio, recomendaciones, fallas con su prueba, pruebas
/// generales y diagnóstico final) con un espacio al final para la firma del encargado de planta. Es un documento NO oficial: el informe técnico se genera al finalizar
/// el trabajo en el equipo (por eso lleva la marca "PRE-INFORME" y no un N° de informe propio).
/// </summary>
public class GeneradorPreInformePdf : IGeneradorPreInformePdf
{
    private const string Primario = "#0057B8";
    private const string Titulo   = "#0F172A";
    private const string Gris     = "#64748B";
    private const string Borde    = "#E2E8F0";
    private const string Fondo    = "#EFF4FF";
    private const string Rojo     = "#B91C1C";

    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    private static string Num(decimal? n) => n is null ? "—" : n.Value.ToString("0.####", Inv);
    private static string Texto(string? s) => string.IsNullOrWhiteSpace(s) ? "—" : s.Trim();
    private static string SiNo(bool v) => v ? "Sí" : "No";

    public static string Severidad(string? s) => s switch
    {
        "baja" => "Baja", "media" => "Media", "alta" => "Alta", "critica" => "Crítica", _ => Texto(s),
    };

    public static string EstadoEquipo(string? s) => s switch
    {
        "operativo" => "Operativo", "con_observaciones" => "Operativo con observaciones", "inoperativo" => "Inoperativo", _ => Texto(s),
    };

    public static string Resultado(string? r) => r switch
    {
        "conforme" => "Conforme", "no_conforme" => "Fuera de EMP", _ => "—",
    };

    /// <summary>Posición de una lectura de excentricidad (igual que la app): 1 centro, 2 a 5 esquinas.</summary>
    public static string Posicion(int? p) => p == 1 ? "Centro" : p is >= 2 ? $"Esquina {p}" : "—";

    public byte[] Generar(DatosPreInformePdf datos)
    {
        var c = datos.Cabecera;
        var d = c.Datos;
        var tipoEquipo = c.Opciones.TiposEquipo.FirstOrDefault(t => t.Codigo == c.Detalle.TipoEquipo)?.Nombre ?? c.Detalle.TipoEquipo;

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
                            t.Item().Text("PRE-INFORME TÉCNICO").FontSize(18).Bold().FontColor(Primario);
                            t.Item().Text($"{d.TipoOrden} {d.NumeroOs}{(string.IsNullOrWhiteSpace(d.NumeroRq) ? "" : $" · RQ {d.NumeroRq}")}").FontColor(Gris);
                        });
                        r.ConstantItem(150).AlignRight().Column(t =>
                        {
                            t.Item().AlignRight().Text("DOCUMENTO NO OFICIAL").Bold().FontSize(8.5f).FontColor(Rojo);
                            t.Item().AlignRight().Text(d.Generado && !string.IsNullOrWhiteSpace(d.NumeroInforme) ? $"Informe N° {d.NumeroInforme}" : "N° de informe: se asigna al generar").FontSize(8).FontColor(Gris);
                        });
                    });
                    col.Item().PaddingTop(6).PaddingBottom(6).LineHorizontal(1).LineColor(Borde);
                });

                page.Content().Column(col =>
                {
                    col.Spacing(9);

                    Seccion(col, "Cliente y servicio", new[]
                    {
                        ("Empresa", $"{Texto(d.Empresa)}{(string.IsNullOrWhiteSpace(d.Ruc) ? "" : $" · RUC {d.Ruc}")}"),
                        ("Dirección", Texto(d.Direccion)),
                        ("Contacto", $"{Texto(d.Contacto)}{(string.IsNullOrWhiteSpace(d.ContactoCargo) ? "" : $" · {d.ContactoCargo}")}{(string.IsNullOrWhiteSpace(d.ContactoTelefono) ? "" : $" · {d.ContactoTelefono}")}"),
                        ("Tipo de servicio", Texto(d.TipoServicio)),
                        ("Fecha y horario", $"{Texto(d.Fecha)} · {Texto(d.HoraInicio)} a {Texto(d.HoraFin)}"),
                        ("Técnico", Texto(d.Tecnico)),
                        ("Atiende en planta", $"{Texto(d.ResponsableNombre)}{(string.IsNullOrWhiteSpace(d.ResponsableCargo) ? "" : $" · {d.ResponsableCargo}")}{(string.IsNullOrWhiteSpace(d.ResponsableTelefono) ? "" : $" · {d.ResponsableTelefono}")}"),
                    });

                    Seccion(col, "Especificaciones del equipo", new[]
                    {
                        ("Marca · modelo", $"{Texto(d.Marca)} · {Texto(d.Modelo)}"),
                        ("Serie", Texto(d.NumSerie)),
                        ("Código cliente · TW", $"{Texto(d.CodigoCliente)} · {Texto(d.CodigoTw)}"),
                        ("Capacidad máx. · d · e", $"{Texto(d.CapacidadMax)} · {Texto(d.D)} · {Texto(d.E)}"),
                        ("Clase · ubicación", $"{Texto(d.Clase)} · {Texto(d.Ubicacion)}"),
                    });

                    // Detalle del servicio
                    col.Item().Column(s =>
                    {
                        s.Spacing(4);
                        s.Item().Text("Detalle del servicio").Bold().FontSize(11).FontColor(Primario);
                        s.Item().Text($"Tipo de equipo: {Texto(tipoEquipo)} · Anillos de fijación: {(c.Detalle.AnillosFijacion is { } a ? SiNo(a) : "—")}");
                        if (c.Detalle.Celdas.Count > 0) s.Item().Text($"Celdas (mV): {string.Join(" · ", c.Detalle.Celdas.Select(x => Num(x)))}");
                        s.Item().Text($"Pruebas por sumatoria hasta: {Num(c.Detalle.SumatoriaHasta)} · por comparación hasta: {Num(c.Detalle.ComparacionHasta)}");
                        var hechos = c.Detalle.Checklist.Where(p => p.Marcado).OrderBy(p => p.Orden).Select(p => p.Titulo).ToList();
                        s.Item().Text(hechos.Count == 0 ? "Trabajos realizados: —" : "Trabajos realizados:").FontColor(Titulo);
                        foreach (var h in hechos) s.Item().PaddingLeft(10).Text($"• {h}");
                    });

                    // Recomendaciones
                    col.Item().Column(s =>
                    {
                        s.Spacing(3);
                        s.Item().Text("Recomendaciones inmediatas").Bold().FontSize(11).FontColor(Primario);
                        if (c.Recomendaciones.Count == 0) s.Item().Text("Sin recomendaciones.").FontColor(Gris);
                        foreach (var r in c.Recomendaciones) s.Item().PaddingLeft(10).Text($"• {r.Titulo}{(string.IsNullOrWhiteSpace(r.Descripcion) ? "" : $" — {r.Descripcion}")}");
                    });

                    // Fallas y su prueba
                    col.Item().Column(s =>
                    {
                        s.Spacing(5);
                        s.Item().Text("Fallas y su prueba").Bold().FontSize(11).FontColor(Primario);
                        if (c.Fallas.Count == 0) s.Item().Text("Sin fallas.").FontColor(Gris);
                        var n = 0;
                        foreach (var f in c.Fallas)
                        {
                            n++;
                            s.Item().Border(1).BorderColor(Borde).Padding(6).Column(fc =>
                            {
                                fc.Spacing(3);
                                fc.Item().Text($"{n}. {Texto(f.ClasificacionNombre ?? f.Clasificacion)} · {Texto(f.ComponenteNombre ?? f.Componente)} — Severidad {Severidad(f.Severidad)}").Bold();
                                fc.Item().Text(Texto(f.Descripcion));
                                if (f.Fotos.Count > 0) fc.Item().Text($"Fotos de la falla: {f.Fotos.Count}").FontColor(Gris).FontSize(8.5f);
                                if (f.Pruebas.Count > 0)
                                    fc.Item().Table(t =>
                                    {
                                        t.ColumnsDefinition(cd => { cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); });
                                        foreach (var h in new[] { "Prueba", "Carga L", "Indicación I", "Error E", "EMP", "Resultado" })
                                            t.Cell().Background(Fondo).BorderBottom(1).BorderColor(Borde).Padding(3).Text(h).Bold().FontSize(8);
                                        foreach (var p in f.Pruebas)
                                        {
                                            t.Cell().Padding(3).Text(p.Tipo == "excentricidad" ? $"Exc. {Posicion(p.Posicion)}" : p.Tipo == "pesaje" ? "Pesaje" : Texto(p.Tipo)).FontSize(8.5f);
                                            t.Cell().Padding(3).Text(Num(p.Carga)).FontSize(8.5f);
                                            t.Cell().Padding(3).Text(Num(p.Indicacion)).FontSize(8.5f);
                                            t.Cell().Padding(3).Text(Num(p.Error)).FontSize(8.5f);
                                            t.Cell().Padding(3).Text(p.Emp is null ? "—" : $"±{Num(p.Emp)}").FontSize(8.5f);
                                            t.Cell().Padding(3).Text(Resultado(p.Resultado)).FontSize(8.5f);
                                        }
                                    });
                            });
                        }
                    });

                    // Pruebas generales
                    col.Item().Column(s =>
                    {
                        s.Spacing(4);
                        s.Item().Text("Pruebas generales (Ensayos y Calibración)").Bold().FontSize(11).FontColor(Primario);
                        var pg = c.PruebasGenerales;
                        if (!string.IsNullOrWhiteSpace(pg.ErrorCritico)) s.Item().Text($"Error crítico: {pg.ErrorCritico}").FontColor(Rojo).Bold();
                        if (pg.Pesaje.Count > 0)
                        {
                            s.Item().Text("Pesaje (linealidad)").Bold().FontSize(9);
                            s.Item().Table(t =>
                            {
                                t.ColumnsDefinition(cd => { cd.ConstantColumn(28); cd.RelativeColumn(); cd.RelativeColumn(); cd.RelativeColumn(); cd.RelativeColumn(); cd.RelativeColumn(); });
                                foreach (var h in new[] { "N°", "Carga L", "Indicación I", "Error E", "EMP", "Resultado" })
                                    t.Cell().Background(Fondo).BorderBottom(1).BorderColor(Borde).Padding(3).Text(h).Bold().FontSize(8);
                                foreach (var l in pg.Pesaje)
                                {
                                    t.Cell().Padding(3).Text(l.Orden.ToString(Inv)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Num(l.Carga)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Num(l.Indicacion)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Num(l.Error)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(l.Emp is null ? "—" : $"±{Num(l.Emp)}").FontSize(8.5f);
                                    t.Cell().Padding(3).Text(l.Critico ? "Error crítico" : Resultado(l.Resultado)).FontSize(8.5f);
                                }
                            });
                        }
                        foreach (var g in pg.Excentricidad)
                        {
                            s.Item().Text($"Excentricidad · carga {Num(g.Carga)}").Bold().FontSize(9);
                            s.Item().Table(t =>
                            {
                                t.ColumnsDefinition(cd => { cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); cd.RelativeColumn(2); });
                                foreach (var h in new[] { "Posición", "Indicación I", "Error E", "EMP", "Resultado" })
                                    t.Cell().Background(Fondo).BorderBottom(1).BorderColor(Borde).Padding(3).Text(h).Bold().FontSize(8);
                                foreach (var l in g.Lecturas)
                                {
                                    t.Cell().Padding(3).Text(Posicion(l.Orden)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Num(l.Indicacion)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(Num(l.Error)).FontSize(8.5f);
                                    t.Cell().Padding(3).Text(l.Emp is null ? "—" : $"±{Num(l.Emp)}").FontSize(8.5f);
                                    t.Cell().Padding(3).Text(l.Critico ? "Error crítico" : Resultado(l.Resultado)).FontSize(8.5f);
                                }
                            });
                        }
                        if (pg.Pesaje.Count == 0 && pg.Excentricidad.Count == 0) s.Item().Text("Sin lecturas registradas.").FontColor(Gris);
                        if (!string.IsNullOrWhiteSpace(c.ComentarioPruebas)) s.Item().Text($"Comentario: {c.ComentarioPruebas}");
                    });

                    // Diagnóstico final
                    var dg = c.Diagnostico;
                    Seccion(col, "Diagnóstico final", new[]
                    {
                        ("Severidad general", Severidad(dg.SeveridadGeneral)),
                        ("Estado del equipo", EstadoEquipo(dg.EstadoEquipo)),
                        ("Revisión de Jefatura", SiNo(dg.RevisionJefatura)),
                        ("Precotización", SiNo(dg.Precotizacion)),
                        ("Segunda visita", SiNo(dg.SegundaVisita)),
                        ("Aplica garantía", SiNo(dg.AplicaGarantia)),
                    });

                    // Conformidad: espacio para la firma del encargado de planta (no se parte entre páginas)
                    col.Item().PaddingTop(10).ShowEntire().Border(1).BorderColor(Borde).Padding(10).Column(f =>
                    {
                        f.Spacing(4);
                        f.Item().Text("Conformidad del encargado de planta").Bold().FontSize(11).FontColor(Primario);
                        f.Item().Text("Recibí este pre-informe. El informe técnico oficial se emitirá al finalizar el trabajo en el equipo.").FontColor(Gris).FontSize(8.5f);
                        f.Item().Height(64);
                        f.Item().LineHorizontal(1).LineColor(Titulo);
                        f.Item().Text("Firma").FontSize(8.5f).FontColor(Gris);
                        f.Item().PaddingTop(6).Row(r =>
                        {
                            r.Spacing(14);
                            r.RelativeItem().Column(x =>
                            {
                                x.Item().Text(Texto(d.ResponsableNombre)).Bold();
                                x.Item().LineHorizontal(0.6f).LineColor(Gris);
                                x.Item().Text("Nombre").FontSize(8).FontColor(Gris);
                            });
                            r.RelativeItem().Column(x =>
                            {
                                x.Item().Text(string.IsNullOrWhiteSpace(d.ResponsableCargo) ? " " : d.ResponsableCargo).Bold();
                                x.Item().LineHorizontal(0.6f).LineColor(Gris);
                                x.Item().Text("Cargo").FontSize(8).FontColor(Gris);
                            });
                            r.RelativeItem().Column(x =>
                            {
                                x.Item().Text(" ");
                                x.Item().LineHorizontal(0.6f).LineColor(Gris);
                                x.Item().Text("DNI").FontSize(8).FontColor(Gris);
                            });
                            r.RelativeItem().Column(x =>
                            {
                                x.Item().Text(" ");
                                x.Item().LineHorizontal(0.6f).LineColor(Gris);
                                x.Item().Text("Fecha").FontSize(8).FontColor(Gris);
                            });
                        });
                    });
                });

                page.Footer().Row(r =>
                {
                    r.RelativeItem().Text($"Pre-informe generado el {datos.GeneradoEn:dd/MM/yyyy HH:mm} (hora de Lima) por la app de campo de Total Weight. No reemplaza al informe técnico oficial.").FontSize(7.5f).FontColor(Gris);
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
