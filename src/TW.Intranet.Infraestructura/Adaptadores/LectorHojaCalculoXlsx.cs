using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Xml;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Lector de hojas de cálculo sin librerías externas: .xlsx (Office Open XML: un zip con XML) y .csv.
/// Lee la primera hoja visible con datos y devuelve el texto de cada celda. El formato .xls (Excel 97-2003)
/// no se soporta: se pide guardarlo como .xlsx.
/// </summary>
public class LectorHojaCalculoXlsx : ILectorHojaCalculo
{
    private const int  MaxColumnas        = 60;
    private const long MaxBytesDescomprimidos = 60L * 1024 * 1024;   // protección contra archivos "zip bomb"

    private static readonly XmlReaderSettings ConfigXml = new()
    {
        DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, IgnoreComments = true, IgnoreWhitespace = false,
    };

    public ResultadoLecturaHoja Leer(Stream contenido, string nombreArchivo, int maxFilas)
    {
        try
        {
            using var memoria = new MemoryStream();
            contenido.CopyTo(memoria);
            var bytes = memoria.ToArray();
            if (bytes.Length == 0) return new(null, "El archivo está vacío.");

            var extension = Path.GetExtension(nombreArchivo ?? "").ToLowerInvariant();
            if (bytes.Length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0)
                return new(null, "El formato .xls (Excel 97-2003) no es compatible. Ábralo en Excel y guárdelo como .xlsx.");
            if (extension == ".csv" || extension == ".txt")
                return LeerCsv(bytes, maxFilas);
            if (bytes.Length < 4 || bytes[0] != (byte)'P' || bytes[1] != (byte)'K')
                return new(null, "El archivo no es un Excel válido. Use un archivo .xlsx o .csv.");

            using var zip = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
            return LeerXlsx(zip, maxFilas);
        }
        catch (Exception ex) when (ex is InvalidDataException or XmlException or IOException or FormatException)
        {
            return new(null, "No se pudo leer el archivo: está dañado o no es un Excel .xlsx válido.");
        }
    }

    public ResultadoLecturaLibro LeerLibro(Stream contenido, string nombreArchivo, int maxFilasPorHoja)
    {
        try
        {
            using var memoria = new MemoryStream();
            contenido.CopyTo(memoria);
            var bytes = memoria.ToArray();
            if (bytes.Length == 0) return new(null, "El archivo está vacío.");
            if (bytes.Length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0)
                return new(null, "El formato .xls (Excel 97-2003) no es compatible. Ábralo en Excel y guárdelo como .xlsx.");
            if (bytes.Length < 4 || bytes[0] != (byte)'P' || bytes[1] != (byte)'K')
                return new(null, "El archivo no es un Excel .xlsx válido. Use la plantilla oficial.");

            using var zip = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
            var compartidas = LeerTextosCompartidos(zip);
            var hojas = new List<HojaLeida>();
            foreach (var (nombre, ruta) in ListarHojas(zip))
            {
                var entrada = zip.GetEntry(ruta);
                if (entrada is null) continue;
                if (entrada.Length > MaxBytesDescomprimidos) return new(null, $"La hoja {nombre} es demasiado grande.", nombre);
                var filas = LeerHoja(entrada, compartidas, maxFilasPorHoja, out var excedido);
                if (excedido) return new(null, $"La hoja {nombre} tiene más de {maxFilasPorHoja} filas con datos.", nombre);
                hojas.Add(new HojaLeida(nombre, filas));
            }
            return hojas.Count == 0 ? new(null, "El Excel no tiene hojas.") : new(hojas, null);
        }
        catch (Exception ex) when (ex is InvalidDataException or XmlException or IOException or FormatException)
        {
            return new(null, "No se pudo leer el archivo: está dañado o no es un Excel .xlsx válido.");
        }
    }

    // ══════════════════════ XLSX ══════════════════════

    private static ResultadoLecturaHoja LeerXlsx(ZipArchive zip, int maxFilas)
    {
        var compartidas = LeerTextosCompartidos(zip);
        var hojas       = ListarHojas(zip);
        if (hojas.Count == 0) return new(null, "El Excel no tiene hojas.");

        foreach (var (nombre, ruta) in hojas)
        {
            var entrada = zip.GetEntry(ruta);
            if (entrada is null) continue;
            if (entrada.Length > MaxBytesDescomprimidos) return new(null, "La hoja es demasiado grande.");
            var filas = LeerHoja(entrada, compartidas, maxFilas, out var excedido);
            if (excedido) return new(null, $"El archivo tiene más de {maxFilas} filas con datos.", true);
            if (filas.Count > 0) return new(new HojaLeida(nombre, filas), null);
        }
        return new(null, "El archivo no tiene datos.");
    }

    /// <summary>Hojas visibles en el orden del libro, con la ruta de su XML dentro del zip.</summary>
    private static List<(string Nombre, string Ruta)> ListarHojas(ZipArchive zip)
    {
        var relaciones = new Dictionary<string, string>();
        var rels = zip.GetEntry("xl/_rels/workbook.xml.rels");
        if (rels is not null)
        {
            using var r = XmlReader.Create(rels.Open(), ConfigXml);
            while (r.Read())
                if (r.NodeType == XmlNodeType.Element && r.LocalName == "Relationship")
                {
                    var id = r.GetAttribute("Id"); var destino = r.GetAttribute("Target");
                    if (id is null || destino is null) continue;
                    relaciones[id] = destino.StartsWith('/') ? destino.TrimStart('/') : "xl/" + destino;
                }
        }

        var hojas = new List<(string, string)>();
        var libro = zip.GetEntry("xl/workbook.xml");
        if (libro is null) return hojas;
        using (var r = XmlReader.Create(libro.Open(), ConfigXml))
            while (r.Read())
                if (r.NodeType == XmlNodeType.Element && r.LocalName == "sheet")
                {
                    if (r.GetAttribute("state") is "hidden" or "veryHidden") continue;
                    var nombre = r.GetAttribute("name") ?? "Hoja";
                    var rid = r.GetAttribute("id", "http://schemas.openxmlformats.org/officeDocument/2006/relationships");
                    if (rid is not null && relaciones.TryGetValue(rid, out var ruta)) hojas.Add((nombre, ruta.Replace("/./", "/")));
                }
        return hojas;
    }

    private static List<string> LeerTextosCompartidos(ZipArchive zip)
    {
        var lista = new List<string>();
        var entrada = zip.GetEntry("xl/sharedStrings.xml");
        if (entrada is null) return lista;
        if (entrada.Length > MaxBytesDescomprimidos) throw new InvalidDataException();

        using var r = XmlReader.Create(entrada.Open(), ConfigXml);
        StringBuilder? actual = null;
        int fonetico = 0;
        // ReadElementContentAsString deja el lector en el nodo siguiente (ej. </si>): ese nodo se procesa sin otro Read.
        bool leer = true;
        while (leer ? r.Read() : !r.EOF)
        {
            leer = true;
            if (r.NodeType == XmlNodeType.Element)
            {
                if (r.LocalName == "si") { actual = new StringBuilder(); if (r.IsEmptyElement) { lista.Add(""); actual = null; } }
                else if (r.LocalName == "rPh" && !r.IsEmptyElement) fonetico++;
                else if (r.LocalName == "t" && actual is not null && fonetico == 0 && !r.IsEmptyElement)
                {
                    actual.Append(r.ReadElementContentAsString());
                    leer = false;
                }
            }
            else if (r.NodeType == XmlNodeType.EndElement)
            {
                if (r.LocalName == "rPh") fonetico--;
                else if (r.LocalName == "si" && actual is not null) { lista.Add(actual.ToString()); actual = null; }
            }
        }
        return lista;
    }

    private static List<FilaLeida> LeerHoja(ZipArchiveEntry entrada, List<string> compartidas, int maxFilas, out bool excedido)
    {
        excedido = false;
        var filas = new List<FilaLeida>();
        using var r = XmlReader.Create(entrada.Open(), ConfigXml);

        int numeroFila = 0;
        Dictionary<int, string>? celdas = null;
        int columnaSiguiente = 0;

        while (r.Read())
        {
            if (r.NodeType == XmlNodeType.Element && r.LocalName == "row")
            {
                numeroFila = int.TryParse(r.GetAttribute("r"), out var n) ? n : numeroFila + 1;
                celdas = [];
                columnaSiguiente = 0;
                if (r.IsEmptyElement) celdas = null;
            }
            else if (r.NodeType == XmlNodeType.Element && r.LocalName == "c" && celdas is not null)
            {
                var referencia = r.GetAttribute("r");
                var columna = referencia is null ? columnaSiguiente : IndiceColumna(referencia);
                columnaSiguiente = columna + 1;
                var tipo = r.GetAttribute("t");
                var texto = r.IsEmptyElement ? "" : LeerCelda(r, tipo, compartidas);
                if (columna < MaxColumnas && texto.Length > 0) celdas[columna] = texto.Trim();
            }
            else if (r.NodeType == XmlNodeType.EndElement && r.LocalName == "row" && celdas is not null)
            {
                if (celdas.Count > 0)
                {
                    if (filas.Count >= maxFilas) { excedido = true; return filas; }
                    var ancho = celdas.Keys.Max() + 1;
                    var valores = new string[ancho];
                    for (int i = 0; i < ancho; i++) valores[i] = celdas.TryGetValue(i, out var v) ? v : "";
                    filas.Add(new FilaLeida(numeroFila, valores));
                }
                celdas = null;
            }
        }
        return filas;
    }

    /// <summary>Lee el contenido de &lt;c&gt; (el lector queda en su cierre).</summary>
    private static string LeerCelda(XmlReader r, string? tipo, List<string> compartidas)
    {
        string? valor = null;
        var enLinea = new StringBuilder();
        var profundidad = r.Depth;
        while (r.Read() && !(r.NodeType == XmlNodeType.EndElement && r.Depth == profundidad))
        {
            if (r.NodeType != XmlNodeType.Element || r.IsEmptyElement) continue;
            if (r.LocalName == "v") valor = r.ReadElementContentAsString();
            else if (r.LocalName == "t") enLinea.Append(r.ReadElementContentAsString());
            // ReadElementContentAsString deja el lector en el nodo siguiente: si es el cierre de <c>, terminamos.
            if (r.NodeType == XmlNodeType.EndElement && r.Depth == profundidad) break;
        }

        return tipo switch
        {
            "s"         => int.TryParse(valor, out var i) && i >= 0 && i < compartidas.Count ? compartidas[i] : "",
            "inlineStr" => enLinea.ToString(),
            "str"       => valor ?? "",
            "b"         => valor == "1" ? "VERDADERO" : "FALSO",
            "e"         => "",
            _           => Numero(valor),
        };
    }

    /// <summary>Números como texto: 864429 (no 864429.0 ni 8.64429E+05).</summary>
    private static string Numero(string? valor)
    {
        if (string.IsNullOrWhiteSpace(valor)) return "";
        if (!double.TryParse(valor, NumberStyles.Float, CultureInfo.InvariantCulture, out var d)) return valor;
        if (Math.Abs(d) < 1e15 && d == Math.Floor(d)) return ((long)d).ToString(CultureInfo.InvariantCulture);
        return ((decimal)d).ToString("0.##########", CultureInfo.InvariantCulture);
    }

    /// <summary>"B12" → 1; "AA3" → 26.</summary>
    private static int IndiceColumna(string referencia)
    {
        int col = 0;
        foreach (var c in referencia)
        {
            if (!char.IsLetter(c)) break;
            col = col * 26 + (char.ToUpperInvariant(c) - 'A' + 1);
        }
        return Math.Max(0, col - 1);
    }

    // ══════════════════════ CSV ══════════════════════

    private static ResultadoLecturaHoja LeerCsv(byte[] bytes, int maxFilas)
    {
        string texto;
        try { texto = new UTF8Encoding(false, true).GetString(bytes); }
        catch (DecoderFallbackException) { texto = Encoding.Latin1.GetString(bytes); }   // CSV guardado por Excel en Windows
        texto = texto.TrimStart('﻿');

        var primera = texto.Split('\n', 2)[0];
        var separador = new[] { ';', ',', '\t' }.OrderByDescending(s => primera.Count(c => c == s)).First();

        var filas = new List<FilaLeida>();
        var celdas = new List<string>();
        var actual = new StringBuilder();
        bool comillas = false;
        int numero = 1;

        void CerrarFila()
        {
            celdas.Add(actual.ToString().Trim()); actual.Clear();
            if (celdas.Any(c => c.Length > 0))
                filas.Add(new FilaLeida(numero, celdas.Take(MaxColumnas).ToArray()));
            celdas = [];
            numero++;
        }

        for (int i = 0; i < texto.Length; i++)
        {
            var c = texto[i];
            if (comillas)
            {
                if (c == '"' && i + 1 < texto.Length && texto[i + 1] == '"') { actual.Append('"'); i++; }
                else if (c == '"') comillas = false;
                else actual.Append(c);
            }
            else if (c == '"' && actual.Length == 0) comillas = true;
            else if (c == separador) { celdas.Add(actual.ToString().Trim()); actual.Clear(); }
            else if (c == '\n') { CerrarFila(); if (filas.Count > maxFilas) return new(null, $"El archivo tiene más de {maxFilas} filas con datos.", true); }
            else if (c != '\r') actual.Append(c);
        }
        if (actual.Length > 0 || celdas.Count > 0) CerrarFila();
        if (filas.Count > maxFilas) return new(null, $"El archivo tiene más de {maxFilas} filas con datos.", true);

        return filas.Count == 0 ? new(null, "El archivo no tiene datos.") : new(new HojaLeida("CSV", filas), null);
    }
}
