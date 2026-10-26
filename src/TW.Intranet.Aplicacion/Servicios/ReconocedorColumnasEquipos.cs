using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.Servicios;

/// <summary>
/// Reconocimiento de columnas por reglas (sin IA): busca la fila de encabezados entre las primeras filas y asigna
/// cada encabezado a un dato por sus nombres habituales ("N/S", "Serie", "Marca", "Capacidad", "Ubicación"…).
/// Se usa cuando la IA no está disponible y para completar lo que la IA no reconoció.
/// </summary>
public static partial class ReconocedorColumnasEquipos
{
    /// <summary>Datos que se buscan en el Excel, en orden de prioridad.</summary>
    public static readonly string[] Campos =
        ["numSerie", "codigoTw", "codigoCliente", "equipo", "marca", "modelo", "capacidad", "ubicacion", "sede"];

    public static readonly IReadOnlyDictionary<string, string> NombresCampos = new Dictionary<string, string>
    {
        ["numSerie"]      = "N/S (número de serie)",
        ["codigoTw"]      = "Código TW",
        ["codigoCliente"] = "Código del cliente",
        ["equipo"]        = "Equipo / instrumento",
        ["marca"]         = "Marca",
        ["modelo"]        = "Modelo",
        ["capacidad"]     = "Capacidad / alcance",
        ["ubicacion"]     = "Ubicación en sede",
        ["sede"]          = "Sede",
    };

    /// <summary>Filas revisadas para encontrar los encabezados.</summary>
    public const int FilasMuestra = 15;

    public static (int FilaEncabezado, Dictionary<string, int> Columnas) Reconocer(IReadOnlyList<FilaLeida> filas)
    {
        int mejorFila = 0; Dictionary<string, int> mejor = [];
        foreach (var fila in filas.Take(FilasMuestra))
        {
            var columnas = AsignarEncabezados(fila.Celdas);
            if (columnas.Count > mejor.Count) { mejor = columnas; mejorFila = fila.Numero; }
        }
        if (mejor.Count < 2) { mejor = []; mejorFila = 0; }

        // Código TW por el contenido (EQ-TW-2026-0041), aunque el encabezado no lo diga.
        if (!mejor.ContainsKey("codigoTw"))
        {
            var datos = filas.Where(f => f.Numero > mejorFila).Take(30).ToList();
            var ancho = datos.Count == 0 ? 0 : datos.Max(f => f.Celdas.Count);
            for (int c = 0; c < ancho; c++)
                if (!mejor.ContainsValue(c) && datos.Count(f => c < f.Celdas.Count && PatronCodigoTw().IsMatch(f.Celdas[c])) >= Math.Max(1, datos.Count / 2))
                { mejor["codigoTw"] = c; break; }
        }
        return (mejorFila, mejor);
    }

    /// <summary>
    /// Columnas que el encabezado nombra sin ambigüedad ("N/S", "Código TW", "Código del cliente", "Marca"…).
    /// Mandan sobre lo que deduzca la IA por el contenido: una serie del cliente que empieza con "TW" sigue siendo N/S.
    /// </summary>
    public static Dictionary<string, int> CamposPorEncabezado(IReadOnlyList<string> celdas)
    {
        var r = new Dictionary<string, int>();
        for (int c = 0; c < celdas.Count; c++)
        {
            var campo = Campo(Similitud.Normalizar(celdas[c]), true);
            if (campo is not null && !r.ContainsKey(campo)) r[campo] = c;
        }
        return r;
    }

    /// <summary>¿La columna trae códigos TW (EQ-TW-AAAA-NNNN)? Al menos la mitad de las celdas con dato.</summary>
    public static bool TraeCodigosTw(IReadOnlyList<FilaLeida> filas, int filaEncabezado, int columna)
    {
        var valores = filas.Where(f => f.Numero > filaEncabezado && columna < f.Celdas.Count && f.Celdas[columna].Length > 0)
                           .Take(30).Select(f => f.Celdas[columna]).ToList();
        return valores.Count > 0 && valores.Count(v => PatronCodigoTw().IsMatch(v)) * 2 >= valores.Count;
    }

    private static Dictionary<string, int> AsignarEncabezados(IReadOnlyList<string> celdas)
    {
        var r = new Dictionary<string, int>();
        // Dos pasadas: primero coincidencias fuertes y luego las débiles ("tipo" → equipo, "código" → código del cliente).
        foreach (var fuerte in new[] { true, false })
            for (int c = 0; c < celdas.Count; c++)
            {
                if (r.ContainsValue(c)) continue;
                var campo = Campo(Similitud.Normalizar(celdas[c]), fuerte);
                if (campo is not null && !r.ContainsKey(campo)) r[campo] = c;
            }
        return r;
    }

    private static string? Campo(string h, bool fuerte)
    {
        if (h.Length == 0 || h.Length > 60) return null;
        var p = h.Split(' ');
        bool Tiene(params string[] xs) => xs.Any(x => p.Contains(x));
        bool Empieza(params string[] xs) => xs.Any(x => p.Any(w => w.StartsWith(x)));

        if (fuerte)
        {
            if (h is "ns" or "n s" or "s n" or "sn" or "nro s" or "n/s" || Empieza("serie", "serial")) return "numSerie";
            if (Tiene("tw") && (Empieza("cod") || Tiene("cod"))) return "codigoTw";
            if (h.Contains("total weight")) return "codigoTw";
            if ((Empieza("cod") || Tiene("tag")) && (Tiene("cliente", "interno", "activo", "patrimonial", "inventario", "equipo", "planta")))
                return "codigoCliente";
            if (Tiene("tag")) return "codigoCliente";
            if (Tiene("marca", "fabricante")) return "marca";
            if (Tiene("modelo")) return "modelo";
            if (Empieza("capacidad", "alcance") || h.Contains("cap max") || h.Contains("carga max") || h.Contains("max cap")) return "capacidad";
            if (Empieza("ubicacion") || Tiene("area", "zona", "lugar")) return "ubicacion";
            if (Tiene("sede", "planta", "local", "unidad")) return "sede";
            if (Tiene("equipo", "instrumento", "descripcion", "denominacion", "balanza", "bascula")) return "equipo";
            return null;
        }

        if (Empieza("cod")) return "codigoCliente";
        if (Tiene("tipo", "nombre", "item", "detalle")) return "equipo";
        if (Tiene("rango", "max", "maximo")) return "capacidad";
        return null;
    }

    /// <summary>Letra de la columna (0 → A, 26 → AA).</summary>
    public static string Letra(int indice)
    {
        var s = "";
        for (int n = indice + 1; n > 0; n = (n - 1) / 26) s = (char)('A' + (n - 1) % 26) + s;
        return s;
    }

    [GeneratedRegex(@"^\s*EQ-?TW-?\d{4}-?\d+\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex PatronCodigoTw();
}
