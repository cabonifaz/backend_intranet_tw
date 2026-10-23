using System.Globalization;
using System.Text;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// OC multi-propuesta (ticket C): pool consolidado de los ítems de todas las propuestas vinculadas contra los conceptos
/// de la OC.
/// 1. Pool: la identidad de un ítem es (descripción normalizada, precio unitario, alcance) en la moneda de su propuesta.
///    Dos ítems son el mismo solo si coinciden los tres; si son el mismo, se suman sus cantidades (con el aporte de cada
///    propuesta). La descripción normalizada va en minúsculas, sin tildes ni signos y sin conectores ("de", "la"…).
/// 2. Cada concepto de la OC se asigna a UN ítem del pool: la descripción debe corresponder (igual, mismas palabras, todas
///    las palabras de una en la otra, o los primeros 20 caracteres de una dentro de la otra si tiene al menos 10) y, si
///    la OC trae precio, el precio debe coincidir con una tolerancia de ±1% (mínimo un céntimo). Con propuestas en otra
///    moneda, el precio del pool se convierte a la moneda de la OC con el tipo de cambio. Entre varios candidatos gana la
///    mejor descripción, luego el que menciona su alcance en el texto de la OC y luego el precio más cercano.
/// 3. Cantidad OC = pool → ok; menor → advertencia "faltan N"; mayor → "sobran N"; ítem del pool sin concepto en la OC →
///    "falta en la OC"; concepto de la OC sin ítem → adicional en la OC.
/// </summary>
internal static class ConsolidacionConceptosOrdenCompra
{
    private sealed class Grupo
    {
        public required string  Clave       { get; init; }
        public required string  Descripcion { get; init; }
        public required decimal Precio      { get; init; }
        public required string? Alcance     { get; init; }
        public required string  ClaveAlcance { get; init; }
        public required int     IdMoneda    { get; init; }
        public decimal          Cantidad    { get; set; }
        public List<ItemAporteDto> Aportes  { get; } = [];
    }

    private static readonly HashSet<string> Conectores = ["de", "del", "la", "las", "el", "los", "y", "e", "en", "con", "para", "por", "a", "al"];

    /// <summary>Minúsculas, sin tildes, solo letras/dígitos separados por un espacio.</summary>
    public static string Normalizar(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return "";
        var sb = new StringBuilder(texto.Length);
        foreach (var c in texto.Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(char.IsLetterOrDigit(c) ? char.ToLowerInvariant(c) : ' ');
        }
        return string.Join(' ', sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>Descripción normalizada sin conectores ("Mantenimiento de celda de carga" → "mantenimiento celda carga").</summary>
    public static string Clave(string? texto) =>
        string.Join(' ', Normalizar(texto).Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => !Conectores.Contains(w)));

    private static string Compacto(string clave) => clave.Replace(" ", "");

    /// <summary>
    /// 3 iguales; 2 mismas palabras; 1 todas las palabras (2 o más) de una en la otra, o los primeros 20 alfanuméricos de
    /// una dentro de la otra (si tiene al menos 10); 0 no corresponden. Recibe claves (sin conectores).
    /// </summary>
    private static int Puntaje(string a, string b)
    {
        if (a.Length == 0 || b.Length == 0) return 0;
        if (a == b) return 3;
        var pa = a.Split(' ').ToHashSet();
        var pb = b.Split(' ').ToHashSet();
        if (pa.SetEquals(pb)) return 2;
        var (menor, mayor) = pa.Count <= pb.Count ? (pa, pb) : (pb, pa);
        if (menor.Count >= 2 && menor.IsSubsetOf(mayor)) return 1;
        var ca = Compacto(a);
        var cb = Compacto(b);
        var prefijoA = ca.Length > 20 ? ca[..20] : ca;
        var prefijoB = cb.Length > 20 ? cb[..20] : cb;
        return (prefijoA.Length >= 10 && cb.Contains(prefijoA, StringComparison.Ordinal))
            || (prefijoB.Length >= 10 && ca.Contains(prefijoB, StringComparison.Ordinal)) ? 1 : 0;
    }

    /// <summary>Precios iguales con tolerancia de ±1% (mínimo un céntimo).</summary>
    public static bool MismoPrecio(decimal a, decimal b) => Math.Abs(a - b) <= Math.Max(0.01m, Math.Abs(b) * 0.01m);

    private static string N(decimal v) => v.ToString("0.##", CultureInfo.InvariantCulture);

    /// <summary>
    /// Devuelve el pool consolidado y llena CompartidoConPropuestas en los conceptos de cada evaluación de la IA.
    /// </summary>
    /// <param name="idMonedaOc">Moneda de la OC.</param>
    /// <param name="tipoCambio">Soles por 1 unidad de moneda extranjera (para comparar precios entre monedas).</param>
    /// <param name="monedas">Catálogo de monedas (para saber cuál es PEN).</param>
    public static List<ItemConsolidadoOcDto> Calcular(
        IReadOnlyList<ConceptoOrdenCompraDto> conceptosOc, IReadOnlyList<ItemPropuestaIaDto> items,
        IReadOnlyList<long> idsVinculadas, IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones,
        int? idMonedaOc = null, decimal? tipoCambio = null, IReadOnlyList<MonedaOrdenCompraDto>? monedas = null)
    {
        monedas ??= [];
        string? Codigo(int? id) => monedas.FirstOrDefault(m => m.Id == id)?.Codigo;
        string? Simbolo(int? id) => monedas.FirstOrDefault(m => m.Id == id)?.Simbolo;

        // Precio de un ítem (moneda de su propuesta) en la moneda de la OC; null si no se puede convertir
        decimal? EnMonedaOc(decimal precio, int idMoneda)
        {
            if (idMonedaOc is null || idMoneda == 0 || idMoneda == idMonedaOc) return precio;
            if (tipoCambio is not > 0) return null;
            var oc = Codigo(idMonedaOc);
            var prop = Codigo(idMoneda);
            if (prop == "PEN") return Math.Round(precio / tipoCambio.Value, 4);  // OC en moneda extranjera
            if (oc == "PEN")   return Math.Round(precio * tipoCambio.Value, 4);  // OC en soles
            return null;
        }

        // 1. Pool por (descripción, precio, alcance) en la moneda de cada propuesta
        var grupos = new List<Grupo>();
        foreach (var i in items.Where(i => idsVinculadas.Contains(i.IdPropuesta)))
        {
            var clave = Clave(i.Descripcion);
            if (clave.Length == 0) continue;
            var precio = Math.Round(i.PrecioUnitario, 2);
            var claveAlcance = Normalizar(i.Alcance);
            var g = grupos.FirstOrDefault(x => x.Clave == clave && x.Precio == precio && x.ClaveAlcance == claveAlcance
                                               && x.IdMoneda == i.IdMoneda);
            if (g is null)
            {
                g = new Grupo
                {
                    Clave = clave, Descripcion = i.Descripcion.Trim(), Precio = precio,
                    Alcance = string.IsNullOrWhiteSpace(i.Alcance) ? null : i.Alcance.Trim(), ClaveAlcance = claveAlcance,
                    IdMoneda = i.IdMoneda,
                };
                grupos.Add(g);
            }
            g.Cantidad += i.Cantidad;
            var aporte = g.Aportes.FindIndex(a => a.IdPropuesta == i.IdPropuesta);
            if (aporte < 0) g.Aportes.Add(new ItemAporteDto(i.IdPropuesta, i.Numero, i.Cantidad, precio));
            else g.Aportes[aporte] = g.Aportes[aporte] with { Cantidad = g.Aportes[aporte].Cantidad + i.Cantidad };
        }

        // 2. Cada concepto de la OC al ítem del pool que mejor le corresponde
        var oc = conceptosOc.Select(c =>
        {
            decimal? precio = c.PrecioUnitario
                ?? (c.Subtotal is { } st && c.Cantidad is > 0 ? Math.Round(st / c.Cantidad.Value, 4) : null);
            return (Concepto: c, Clave: Clave(c.Descripcion), Texto: Normalizar(c.Descripcion), Precio: precio);
        }).ToList();

        var asignado = new int[oc.Count];
        for (var k = 0; k < oc.Count; k++)
        {
            asignado[k] = -1;
            (int Desc, int Alcance, decimal Distancia) mejor = (0, 0, decimal.MaxValue);
            for (var gi = 0; gi < grupos.Count; gi++)
            {
                var g = grupos[gi];
                var desc = Puntaje(g.Clave, oc[k].Clave);
                if (desc == 0) continue;
                var precioPool = EnMonedaOc(g.Precio, g.IdMoneda);
                decimal distancia = 0;
                if (oc[k].Precio is { } po && precioPool is { } pp)
                {
                    if (!MismoPrecio(po, pp)) continue;   // mismo nombre, otro precio: es otro ítem
                    distancia = Math.Abs(po - pp);
                }
                var alcance = g.ClaveAlcance.Length > 0 && oc[k].Texto.Contains(g.ClaveAlcance, StringComparison.Ordinal) ? 1 : 0;
                var candidato = (desc, alcance, distancia);
                if (candidato.desc > mejor.Desc
                    || (candidato.desc == mejor.Desc && candidato.alcance > mejor.Alcance)
                    || (candidato.desc == mejor.Desc && candidato.alcance == mejor.Alcance && candidato.distancia < mejor.Distancia))
                {
                    mejor = candidato;
                    asignado[k] = gi;
                }
            }
        }

        // 3. Comparación de cantidades por ítem del pool
        var resultado = new List<ItemConsolidadoOcDto>();
        for (var gi = 0; gi < grupos.Count; gi++)
        {
            var g = grupos[gi];
            var enOc = Enumerable.Range(0, oc.Count).Where(k => asignado[k] == gi).ToList();
            var cantidades = enOc.Select(k => oc[k].Concepto.Cantidad).Where(q => q is not null).Select(q => q!.Value).ToList();
            decimal? cantidadOc = cantidades.Count > 0 ? cantidades.Sum() : null;
            decimal? precioOc = enOc.Select(k => oc[k].Precio).FirstOrDefault(p => p is not null);
            var detallePool = g.Aportes.Count > 1
                ? $" Pool de {N(g.Cantidad)}: {string.Join(", ", g.Aportes.Select(a => $"{N(a.Cantidad)} de {a.Numero}"))}."
                : "";

            string severidad, mensaje;
            decimal? diferencia = null;
            if (enOc.Count == 0)
            {
                severidad = "advertencia";
                mensaje   = $"Falta en la OC: {N(g.Cantidad)} unidad(es) de {string.Join(", ", g.Aportes.Select(a => a.Numero))}.";
                diferencia = g.Cantidad;
            }
            else if (cantidadOc is null)
            {
                severidad = "ok";
                mensaje   = $"Está en la OC (no indica la cantidad).{detallePool}";
            }
            else
            {
                diferencia = g.Cantidad - cantidadOc.Value;
                (severidad, mensaje) = diferencia.Value switch
                {
                    0   => ("ok", $"Está en la OC: {N(cantidadOc.Value)} unidad(es).{detallePool}"),
                    > 0 => ("advertencia", $"Faltan {N(diferencia.Value)} unidad(es): la OC pide {N(cantidadOc.Value)} y las propuestas suman {N(g.Cantidad)}.{detallePool}"),
                    _   => ("advertencia", $"Sobran {N(-diferencia.Value)} unidad(es): la OC pide {N(cantidadOc.Value)} y las propuestas suman {N(g.Cantidad)}.{detallePool}"),
                };
            }

            resultado.Add(new ItemConsolidadoOcDto(g.Clave, g.Descripcion, g.Aportes.Select(a => a.IdPropuesta).ToList(), g.Cantidad,
                                                   enOc.Count > 0, cantidadOc, severidad, mensaje)
            {
                PrecioUnitario      = g.Precio,
                MonedaSimbolo       = Simbolo(g.IdMoneda),
                Alcance             = g.Alcance,
                CantidadEnPool      = g.Cantidad,
                CantidadEnOc        = cantidadOc,
                Diferencia          = diferencia,
                PrecioUnitarioOc    = precioOc,
                AportesPorPropuesta = [.. g.Aportes],
            });
        }

        // 4. Conceptos de la OC sin ítem en el pool: adicionales
        for (var k = 0; k < oc.Count; k++)
        {
            if (asignado[k] >= 0 || oc[k].Clave.Length == 0) continue;
            var c = oc[k].Concepto;
            var mismoNombre = grupos.Any(g => Puntaje(g.Clave, oc[k].Clave) > 0);
            resultado.Add(new ItemConsolidadoOcDto(oc[k].Clave, c.Descripcion.Trim(), [], 0, true, c.Cantidad, "advertencia",
                mismoNombre
                    ? "Adicional en la OC: las propuestas tienen este ítem, pero con otro precio."
                    : "Adicional en la OC: no está en ninguna propuesta vinculada.")
            {
                CantidadEnOc     = c.Cantidad,
                PrecioUnitarioOc = oc[k].Precio,
                MonedaSimbolo    = Simbolo(idMonedaOc),
                Diferencia       = c.Cantidad is { } q ? -q : null,
            });
        }

        // 5. En cada concepto evaluado por la IA: con qué otras propuestas comparte el ítem
        foreach (var e in evaluaciones ?? [])
            foreach (var c in e.Conceptos)
            {
                var clave = Clave(c.Descripcion);
                c.CompartidoConPropuestas = grupos
                    .Where(g => g.Aportes.Any(a => a.IdPropuesta == e.IdPropuesta) && Puntaje(g.Clave, clave) > 0)
                    .SelectMany(g => g.Aportes.Select(a => a.IdPropuesta))
                    .Where(id => id != e.IdPropuesta)
                    .Distinct()
                    .ToList();
            }

        return resultado;
    }
}
