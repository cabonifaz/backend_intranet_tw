using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Xml;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// HU-25 — Genera archivos .xlsx (SpreadsheetML) solo con la BCL: el .xlsx es un ZIP de XML.
/// Encabezados en negrita y fondo gris, fila de encabezado inmovilizada, autofiltro,
/// fechas con formato dd/mm/yyyy hh:mm y números con 2 decimales.
/// </summary>
public class GeneradorExcelXlsx : IGeneradorExcel
{
    private const string NsMain = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    private const string NsRel  = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

    // Estilos (índices de cellXfs): 0 normal, 1 encabezado, 2 fecha, 3 número
    private const int EstiloEncabezado = 1;
    private const int EstiloFecha      = 2;
    private const int EstiloNumero     = 3;

    public byte[] Generar(IReadOnlyList<HojaExcel> hojas)
    {
        if (hojas.Count == 0) throw new ArgumentException("El libro debe tener al menos una hoja.", nameof(hojas));
        var nombres = NombresUnicos(hojas);

        using var memoria = new MemoryStream();
        using (var zip = new ZipArchive(memoria, ZipArchiveMode.Create, leaveOpen: true))
        {
            Escribir(zip, "[Content_Types].xml", w => TiposContenido(w, hojas.Count));
            Escribir(zip, "_rels/.rels", RelacionesRaiz);
            Escribir(zip, "xl/workbook.xml", w => Libro(w, nombres));
            Escribir(zip, "xl/_rels/workbook.xml.rels", w => RelacionesLibro(w, hojas.Count));
            Escribir(zip, "xl/styles.xml", Estilos);
            for (int i = 0; i < hojas.Count; i++)
            {
                var hoja = hojas[i];
                Escribir(zip, $"xl/worksheets/sheet{i + 1}.xml", w => Hoja(w, hoja));
            }
        }
        return memoria.ToArray();
    }

    private static void Escribir(ZipArchive zip, string ruta, Action<XmlWriter> contenido)
    {
        var entrada = zip.CreateEntry(ruta, CompressionLevel.Optimal);
        using var flujo = entrada.Open();
        using var w = XmlWriter.Create(flujo, new XmlWriterSettings { Encoding = new UTF8Encoding(false) });
        w.WriteStartDocument(true);
        contenido(w);
        w.WriteEndDocument();
    }

    /// <summary>Excel exige nombres de hoja únicos, de hasta 31 caracteres y sin : \ / ? * [ ]</summary>
    private static List<string> NombresUnicos(IReadOnlyList<HojaExcel> hojas)
    {
        var usados = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var nombres = new List<string>();
        foreach (var h in hojas)
        {
            var baseNombre = new string((h.Nombre ?? "Hoja").Where(c => !":\\/?*[]".Contains(c)).ToArray()).Trim();
            if (baseNombre.Length == 0) baseNombre = "Hoja";
            if (baseNombre.Length > 31) baseNombre = baseNombre[..31];
            var nombre = baseNombre;
            for (int n = 2; !usados.Add(nombre); n++)
                nombre = (baseNombre.Length > 27 ? baseNombre[..27] : baseNombre) + $" ({n})";
            nombres.Add(nombre);
        }
        return nombres;
    }

    private static void TiposContenido(XmlWriter w, int hojas)
    {
        w.WriteStartElement("Types", "http://schemas.openxmlformats.org/package/2006/content-types");
        Defecto(w, "rels", "application/vnd.openxmlformats-package.relationships+xml");
        Defecto(w, "xml", "application/xml");
        Sobrescribir(w, "/xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
        Sobrescribir(w, "/xl/styles.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml");
        for (int i = 1; i <= hojas; i++)
            Sobrescribir(w, $"/xl/worksheets/sheet{i}.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml");
        w.WriteEndElement();

        static void Defecto(XmlWriter w, string ext, string tipo)
        {
            w.WriteStartElement("Default");
            w.WriteAttributeString("Extension", ext);
            w.WriteAttributeString("ContentType", tipo);
            w.WriteEndElement();
        }
        static void Sobrescribir(XmlWriter w, string parte, string tipo)
        {
            w.WriteStartElement("Override");
            w.WriteAttributeString("PartName", parte);
            w.WriteAttributeString("ContentType", tipo);
            w.WriteEndElement();
        }
    }

    private static void RelacionesRaiz(XmlWriter w)
    {
        w.WriteStartElement("Relationships", "http://schemas.openxmlformats.org/package/2006/relationships");
        Relacion(w, "rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument", "xl/workbook.xml");
        w.WriteEndElement();
    }

    private static void RelacionesLibro(XmlWriter w, int hojas)
    {
        w.WriteStartElement("Relationships", "http://schemas.openxmlformats.org/package/2006/relationships");
        for (int i = 1; i <= hojas; i++)
            Relacion(w, $"rId{i}", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet", $"worksheets/sheet{i}.xml");
        Relacion(w, $"rId{hojas + 1}", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "styles.xml");
        w.WriteEndElement();
    }

    private static void Relacion(XmlWriter w, string id, string tipo, string destino)
    {
        w.WriteStartElement("Relationship");
        w.WriteAttributeString("Id", id);
        w.WriteAttributeString("Type", tipo);
        w.WriteAttributeString("Target", destino);
        w.WriteEndElement();
    }

    private static void Libro(XmlWriter w, List<string> nombres)
    {
        w.WriteStartElement("workbook", NsMain);
        w.WriteAttributeString("xmlns", "r", null, NsRel);
        w.WriteStartElement("sheets", NsMain);
        for (int i = 0; i < nombres.Count; i++)
        {
            w.WriteStartElement("sheet", NsMain);
            w.WriteAttributeString("name", nombres[i]);
            w.WriteAttributeString("sheetId", (i + 1).ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("id", NsRel, $"rId{i + 1}");
            w.WriteEndElement();
        }
        w.WriteEndElement();
        w.WriteEndElement();
    }

    private static void Estilos(XmlWriter w)
    {
        w.WriteStartElement("styleSheet", NsMain);

        w.WriteStartElement("numFmts", NsMain);
        w.WriteAttributeString("count", "1");
        w.WriteStartElement("numFmt", NsMain);
        w.WriteAttributeString("numFmtId", "164");
        w.WriteAttributeString("formatCode", "dd/mm/yyyy hh:mm");
        w.WriteEndElement();
        w.WriteEndElement();

        w.WriteStartElement("fonts", NsMain);
        w.WriteAttributeString("count", "2");
        w.WriteStartElement("font", NsMain); Val(w, "sz", "11"); Val(w, "name", "Calibri"); w.WriteEndElement();
        w.WriteStartElement("font", NsMain); w.WriteElementString("b", NsMain, ""); Val(w, "sz", "11"); Val(w, "name", "Calibri"); w.WriteEndElement();
        w.WriteEndElement();

        w.WriteStartElement("fills", NsMain);
        w.WriteAttributeString("count", "3");
        Relleno(w, "none", null);
        Relleno(w, "gray125", null);
        Relleno(w, "solid", "FFE2E8F0");
        w.WriteEndElement();

        w.WriteStartElement("borders", NsMain);
        w.WriteAttributeString("count", "1");
        w.WriteStartElement("border", NsMain);
        foreach (var lado in new[] { "left", "right", "top", "bottom", "diagonal" }) w.WriteElementString(lado, NsMain, "");
        w.WriteEndElement();
        w.WriteEndElement();

        w.WriteStartElement("cellStyleXfs", NsMain);
        w.WriteAttributeString("count", "1");
        Xf(w, 0, 0, 0, aplicar: false);
        w.WriteEndElement();

        w.WriteStartElement("cellXfs", NsMain);
        w.WriteAttributeString("count", "4");
        Xf(w, numFmt: 0,   font: 0, fill: 0, aplicar: false); // 0 normal
        Xf(w, numFmt: 0,   font: 1, fill: 2, aplicar: true);  // 1 encabezado
        Xf(w, numFmt: 164, font: 0, fill: 0, aplicar: true);  // 2 fecha
        Xf(w, numFmt: 4,   font: 0, fill: 0, aplicar: true);  // 3 número #,##0.00
        w.WriteEndElement();

        w.WriteStartElement("cellStyles", NsMain);
        w.WriteAttributeString("count", "1");
        w.WriteStartElement("cellStyle", NsMain);
        w.WriteAttributeString("name", "Normal");
        w.WriteAttributeString("xfId", "0");
        w.WriteAttributeString("builtinId", "0");
        w.WriteEndElement();
        w.WriteEndElement();

        w.WriteEndElement();

        static void Val(XmlWriter w, string elemento, string valor)
        {
            w.WriteStartElement(elemento, NsMain);
            w.WriteAttributeString("val", valor);
            w.WriteEndElement();
        }
        static void Relleno(XmlWriter w, string patron, string? color)
        {
            w.WriteStartElement("fill", NsMain);
            w.WriteStartElement("patternFill", NsMain);
            w.WriteAttributeString("patternType", patron);
            if (color is not null)
            {
                w.WriteStartElement("fgColor", NsMain);
                w.WriteAttributeString("rgb", color);
                w.WriteEndElement();
            }
            w.WriteEndElement();
            w.WriteEndElement();
        }
        static void Xf(XmlWriter w, int numFmt, int font, int fill, bool aplicar)
        {
            w.WriteStartElement("xf", NsMain);
            w.WriteAttributeString("numFmtId", numFmt.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("fontId", font.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("fillId", fill.ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("borderId", "0");
            if (aplicar)
            {
                if (numFmt != 0) w.WriteAttributeString("applyNumberFormat", "1");
                if (font != 0)   w.WriteAttributeString("applyFont", "1");
                if (fill != 0)   w.WriteAttributeString("applyFill", "1");
            }
            w.WriteEndElement();
        }
    }

    private static void Hoja(XmlWriter w, HojaExcel hoja)
    {
        int columnas = Math.Max(1, hoja.Encabezados.Count);

        w.WriteStartElement("worksheet", NsMain);

        // Encabezado inmovilizado
        w.WriteStartElement("sheetViews", NsMain);
        w.WriteStartElement("sheetView", NsMain);
        w.WriteAttributeString("workbookViewId", "0");
        w.WriteStartElement("pane", NsMain);
        w.WriteAttributeString("ySplit", "1");
        w.WriteAttributeString("topLeftCell", "A2");
        w.WriteAttributeString("activePane", "bottomLeft");
        w.WriteAttributeString("state", "frozen");
        w.WriteEndElement();
        w.WriteEndElement();
        w.WriteEndElement();

        // Ancho de columnas según el contenido (máx. 60)
        w.WriteStartElement("cols", NsMain);
        for (int c = 0; c < columnas; c++)
        {
            int largo = c < hoja.Encabezados.Count ? hoja.Encabezados[c].Length : 8;
            foreach (var fila in hoja.Filas.Take(500))
                if (c < fila.Count) largo = Math.Max(largo, Texto(fila[c]).Length);
            w.WriteStartElement("col", NsMain);
            w.WriteAttributeString("min", (c + 1).ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("max", (c + 1).ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("width", Math.Clamp(largo + 2, 10, 60).ToString(CultureInfo.InvariantCulture));
            w.WriteAttributeString("customWidth", "1");
            w.WriteEndElement();
        }
        w.WriteEndElement();

        w.WriteStartElement("sheetData", NsMain);
        Fila(w, 1, hoja.Encabezados.Cast<object?>().ToList(), encabezado: true);
        for (int i = 0; i < hoja.Filas.Count; i++)
            Fila(w, i + 2, hoja.Filas[i], encabezado: false);
        w.WriteEndElement();

        if (hoja.Encabezados.Count > 0)
        {
            w.WriteStartElement("autoFilter", NsMain);
            w.WriteAttributeString("ref", $"A1:{Columna(columnas - 1)}{hoja.Filas.Count + 1}");
            w.WriteEndElement();
        }

        w.WriteEndElement();
    }

    private static void Fila(XmlWriter w, int numero, IReadOnlyList<object?> celdas, bool encabezado)
    {
        w.WriteStartElement("row", NsMain);
        w.WriteAttributeString("r", numero.ToString(CultureInfo.InvariantCulture));
        for (int c = 0; c < celdas.Count; c++)
        {
            var valor = celdas[c];
            if (valor is null) continue;
            var referencia = $"{Columna(c)}{numero}";
            w.WriteStartElement("c", NsMain);
            w.WriteAttributeString("r", referencia);

            switch (valor)
            {
                case DateTime fecha when !encabezado:
                    w.WriteAttributeString("s", EstiloFecha.ToString(CultureInfo.InvariantCulture));
                    w.WriteElementString("v", NsMain, fecha.ToOADate().ToString(CultureInfo.InvariantCulture));
                    break;
                case decimal or double or float when !encabezado:
                    w.WriteAttributeString("s", EstiloNumero.ToString(CultureInfo.InvariantCulture));
                    w.WriteElementString("v", NsMain, Convert.ToString(valor, CultureInfo.InvariantCulture));
                    break;
                case int or long or short when !encabezado:
                    w.WriteElementString("v", NsMain, Convert.ToString(valor, CultureInfo.InvariantCulture));
                    break;
                case bool b when !encabezado:
                    w.WriteAttributeString("t", "inlineStr");
                    EscribirTexto(w, b ? "Sí" : "No");
                    break;
                default:
                    w.WriteAttributeString("t", "inlineStr");
                    if (encabezado) w.WriteAttributeString("s", EstiloEncabezado.ToString(CultureInfo.InvariantCulture));
                    EscribirTexto(w, Texto(valor));
                    break;
            }
            w.WriteEndElement();
        }
        w.WriteEndElement();
    }

    private static void EscribirTexto(XmlWriter w, string texto)
    {
        w.WriteStartElement("is", NsMain);
        w.WriteStartElement("t", NsMain);
        w.WriteAttributeString("xml", "space", null, "preserve");
        w.WriteString(Limpiar(texto.Length > 32767 ? texto[..32767] : texto));
        w.WriteEndElement();
        w.WriteEndElement();
    }

    /// <summary>Quita los caracteres de control que XML no admite.</summary>
    private static string Limpiar(string texto) =>
        new(texto.Where(c => c == '\t' || c == '\n' || c == '\r' || c >= ' ').ToArray());

    private static string Texto(object? valor) => valor switch
    {
        null       => "",
        DateTime d => d.ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture),
        _          => Convert.ToString(valor, CultureInfo.InvariantCulture) ?? "",
    };

    private static string Columna(int indice)
    {
        var nombre = "";
        for (int n = indice + 1; n > 0; n = (n - 1) / 26)
            nombre = (char)('A' + (n - 1) % 26) + nombre;
        return nombre;
    }
}
