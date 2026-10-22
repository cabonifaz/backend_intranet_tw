using System.Globalization;
using System.Text;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// OC multi-propuesta (ticket C): junta los ítems de todas las propuestas vinculadas en un solo pool (deduplicado por
/// descripción normalizada: minúsculas, sin tildes ni signos, espacios simples y sin conectores como "de", "la", "para")
/// y lo compara contra los conceptos de la OC.
/// Un concepto de la OC corresponde a un ítem si la descripción normalizada es igual, si tienen las mismas palabras sin
/// contar conectores, si todas las palabras de uno están en el otro, o si los primeros 20 caracteres alfanuméricos de uno
/// están dentro del otro (con al menos 10). Cada concepto de la OC se asigna al ítem que mejor le corresponde. Con la evaluación de la IA, un ítem
/// también cuenta como presente si la IA lo marcó "coincide" o "monto_distinto" en alguna propuesta.
/// </summary>
internal static class ConsolidacionConceptosOrdenCompra
{
    private sealed class Grupo
    {
        public required string Clave       { get; init; }
        public required string Descripcion { get; init; }
        public List<long>      Propuestas  { get; } = [];
        public List<string>    Numeros     { get; } = [];
        public decimal         Cantidad    { get; set; }
        public bool            EnOcIa      { get; set; }
    }

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

    private static string Compacto(string normalizado) => normalizado.Replace(" ", "");

    private static readonly HashSet<string> Conectores = ["de", "del", "la", "las", "el", "los", "y", "e", "en", "con", "para", "por", "a", "al"];

    private static HashSet<string> Palabras(string normalizado) =>
        normalizado.Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => !Conectores.Contains(w)).ToHashSet();

    /// <summary>
    /// Qué tan bien corresponden dos descripciones normalizadas: 3 iguales; 2 las mismas palabras sin contar conectores
    /// ("Calibración de balanza" = "Calibracion balanza"); 1 todas las palabras (2 o más) de una dentro de la otra, o los
    /// primeros 20 alfanuméricos de una dentro de la otra (si tiene al menos 10, para que "Servicio" no corresponda a
    /// todo); 0 no corresponden.
    /// </summary>
    private static int Puntaje(string a, string b)
    {
        if (a.Length == 0 || b.Length == 0) return 0;
        if (a == b) return 3;
        var pa = Palabras(a);
        var pb = Palabras(b);
        if (pa.Count > 0 && pa.SetEquals(pb)) return 2;
        var (menor, mayor) = pa.Count <= pb.Count ? (pa, pb) : (pb, pa);
        if (menor.Count >= 2 && menor.IsSubsetOf(mayor)) return 1;
        var ca = Compacto(a);
        var cb = Compacto(b);
        var prefijoA = ca.Length > 20 ? ca[..20] : ca;
        var prefijoB = cb.Length > 20 ? cb[..20] : cb;
        return (prefijoA.Length >= 10 && cb.Contains(prefijoA, StringComparison.Ordinal))
            || (prefijoB.Length >= 10 && ca.Contains(prefijoB, StringComparison.Ordinal)) ? 1 : 0;
    }

    private static bool Corresponden(string a, string b) => Puntaje(a, b) > 0;

    /// <summary>Clave del pool: descripción normalizada sin conectores ("mantenimiento de celda de carga" →
    /// "mantenimiento celda carga"), para juntar el mismo ítem aunque cada propuesta lo redacte un poco distinto.</summary>
    public static string Clave(string? texto) =>
        string.Join(' ', Normalizar(texto).Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(w => !Conectores.Contains(w)));

    /// <summary>
    /// Devuelve el pool consolidado y llena CompartidoConPropuestas en los conceptos de cada evaluación de la IA.
    /// </summary>
    public static List<ItemConsolidadoOcDto> Calcular(
        IReadOnlyList<ConceptoOrdenCompraDto> conceptosOc, IReadOnlyList<ItemPropuestaIaDto> items,
        IReadOnlyList<long> idsVinculadas, IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones)
    {
        // 1. Pool de ítems de las propuestas vinculadas
        var grupos = new List<Grupo>();
        foreach (var i in items.Where(i => idsVinculadas.Contains(i.IdPropuesta)))
        {
            var clave = Clave(i.Descripcion);
            if (clave.Length == 0) continue;
            var g = grupos.FirstOrDefault(x => x.Clave == clave);
            if (g is null)
            {
                g = new Grupo { Clave = clave, Descripcion = i.Descripcion.Trim() };
                grupos.Add(g);
            }
            if (!g.Propuestas.Contains(i.IdPropuesta))
            {
                g.Propuestas.Add(i.IdPropuesta);
                g.Numeros.Add(i.Numero);
            }
            g.Cantidad += i.Cantidad;
        }

        // 2. La IA marcó el ítem como presente en la OC (en alguna propuesta)
        var conceptosIa = (evaluaciones ?? [])
            .SelectMany(e => e.Conceptos.Select(c => (e.IdPropuesta, Concepto: c, Clave: Clave(c.Descripcion))))
            .ToList();
        foreach (var (_, c, clave) in conceptosIa.Where(x => x.Concepto.Estado is "coincide" or "monto_distinto"))
            foreach (var g in grupos.Where(g => Corresponden(g.Clave, clave)))
                g.EnOcIa = true;

        // 3. Conceptos de la OC
        var oc = conceptosOc.Select(c => (Concepto: c, Clave: Clave(c.Descripcion), Usado: false)).ToList();

        // Cada concepto de la OC va al ítem que mejor le corresponde (uno solo, para no contar su cantidad dos veces)
        var asignado = new int[oc.Count];
        for (var k = 0; k < oc.Count; k++)
        {
            asignado[k] = -1;
            var mejor = 0;
            for (var gi = 0; gi < grupos.Count; gi++)
            {
                var pts = Puntaje(grupos[gi].Clave, oc[k].Clave);
                if (pts > mejor) { mejor = pts; asignado[k] = gi; }
            }
            if (asignado[k] >= 0) oc[k] = oc[k] with { Usado = true };
        }

        var resultado = new List<ItemConsolidadoOcDto>();
        for (var gi = 0; gi < grupos.Count; gi++)
        {
            var g = grupos[gi];
            var enOc = Enumerable.Range(0, oc.Count).Where(k => asignado[k] == gi).ToList();

            var presente = enOc.Count > 0 || g.EnOcIa;
            var cantidades = enOc.Select(k => oc[k].Concepto.Cantidad).Where(q => q is not null).Select(q => q!.Value).ToList();
            decimal? cantidadOc = cantidades.Count > 0 ? cantidades.Sum() : null;
            var compartido = g.Propuestas.Count > 1 ? $" Está en {g.Propuestas.Count} propuestas ({string.Join(", ", g.Numeros)})." : "";

            string severidad, mensaje;
            if (!presente)
            {
                severidad = "advertencia";
                mensaje   = $"Falta en la OC: está en {string.Join(", ", g.Numeros)}.";
            }
            else if (cantidadOc is { } q && q != g.Cantidad)
            {
                severidad = "advertencia";
                mensaje   = $"La OC pide {q.ToString("0.##", CultureInfo.InvariantCulture)}; las propuestas suman " +
                            $"{g.Cantidad.ToString("0.##", CultureInfo.InvariantCulture)}.{compartido}";
            }
            else
            {
                severidad = "ok";
                mensaje   = $"Está en la OC.{compartido}";
            }
            resultado.Add(new ItemConsolidadoOcDto(g.Clave, g.Descripcion, [.. g.Propuestas], g.Cantidad, presente, cantidadOc,
                                                   severidad, mensaje));
        }

        // 4. Conceptos de la OC que no están en ninguna propuesta (salvo que la IA los haya emparejado)
        foreach (var (c, clave, usado) in oc)
        {
            if (usado || clave.Length == 0) continue;
            var emparejadoIa = conceptosIa.Any(x => x.Concepto.Estado is "coincide" or "monto_distinto" && Corresponden(x.Clave, clave));
            if (emparejadoIa) continue;
            if (resultado.Any(r => r.EnPropuestas.Count == 0 && r.DescripcionNormalizada == clave)) continue;
            resultado.Add(new ItemConsolidadoOcDto(clave, c.Descripcion.Trim(), [], 0, true, c.Cantidad, "advertencia",
                                                   "Concepto de la OC que no está en ninguna propuesta vinculada."));
        }

        // 5. En cada concepto evaluado por la IA: con qué otras propuestas comparte el ítem
        foreach (var e in evaluaciones ?? [])
            foreach (var c in e.Conceptos)
            {
                var clave = Clave(c.Descripcion);
                c.CompartidoConPropuestas = grupos
                    .Where(g => Corresponden(g.Clave, clave))
                    .SelectMany(g => g.Propuestas)
                    .Where(id => id != e.IdPropuesta)
                    .Distinct()
                    .ToList();
            }

        return resultado;
    }
}
