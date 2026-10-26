using System.Text.Json;
using System.Text.Json.Nodes;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// IA de la importación de equipos de una propuesta con Google Gemini: reconoce las columnas del Excel y elige,
/// entre los candidatos que le pasan las reglas, el equipo del cliente o el suministro del catálogo de cada fila.
/// Solo recibe el texto de las primeras filas y los candidatos ya filtrados (no el inventario completo).
/// </summary>
public class GeminiAsistenteEquipos(HttpClient http, ConfiguracionGemini configuracion)
    : GeminiClienteBase(http, configuracion), IAsistenteIaEquipos
{
    // ══════════════════════ Columnas ══════════════════════

    private const string InstruccionColumnas = """
        Eres un asistente del área comercial de Total Weight (Perú), empresa de calibración y mantenimiento de balanzas,
        básculas, pesas patrón e instrumentos de medición. Recibes las primeras filas de un Excel con el listado de
        equipos de un cliente (cada celda como "letra de columna: texto"). Identifica qué columna trae cada dato.
        Reglas:
        - filaEncabezado: número de la fila que tiene los títulos de las columnas; 0 si el archivo no tiene títulos.
        - Para cada dato devuelve la LETRA de la columna (A, B, C…) o null si no existe. Una columna no se repite.
        - numSerie: número de serie del fabricante (N/S, S/N, serie, serial).
        - codigoTw: código de Total Weight con formato EQ-TW-AAAA-NNNN.
        - codigoCliente: tag, código interno o código de activo del cliente (no la serie).
        - equipo: descripción o tipo de equipo/instrumento (ej. "Báscula camionera", "Balanza analítica").
        - marca y modelo del equipo. Si una sola columna trae "marca modelo", asígnala a modelo.
        - capacidad: capacidad máxima, alcance o rango (ej. "80 000 kg", "220 g x 0.1 mg").
        - ubicacion: área o lugar dentro de la planta. sede: planta, sede o unidad del cliente.
        - El TÍTULO de la columna manda sobre su contenido: si el título dice "N/S", "S/N", "serie" o "número de serie",
          esa columna es numSerie aunque sus valores empiecen con "TW" (son series del cliente). codigoTw solo es la
          columna cuyo título menciona "código TW" / "Total Weight" o, sin título, la que trae valores EQ-TW-AAAA-NNNN.
          Un título "código del cliente", "tag" o "código interno" es codigoCliente.
        - Usa el contenido de las filas solo cuando el título no existe o es ambiguo.
        - confianza: de 0 a 100.
        """;

    private static readonly string[] CamposColumnas = ReconocedorColumnasEquipos.Campos;

    private static JsonObject EsquemaColumnas()
    {
        var props = new Dictionary<string, JsonObject> { ["filaEncabezado"] = Tipo("NUMBER", false) };
        foreach (var c in CamposColumnas) props[c] = Tipo("STRING", true);
        props["confianza"] = Tipo("NUMBER", false);
        return Objeto(props, ["filaEncabezado", "numSerie", "confianza"]);
    }

    public async Task<ResultadoIa<MapeoColumnasIaDto>> ReconocerColumnasAsync(IReadOnlyList<FilaLeida> muestra, CancellationToken ct)
    {
        if (!Disponible) return new(null, "La IA no está configurada.");

        var texto = string.Join('\n', muestra.Select(f =>
            $"Fila {f.Numero}: " + string.Join(" | ", f.Celdas
                .Select((c, i) => (c, i))
                .Where(x => x.c.Length > 0)
                .Select(x => $"{ReconocedorColumnasEquipos.Letra(x.i)}: {Recortar(x.c, 60)}"))));
        var partes = new JsonArray { new JsonObject { ["text"] = "Filas del archivo:\n" + texto } };

        var (salida, error) = await GenerarAsync(InstruccionColumnas, partes, EsquemaColumnas(), ct);
        if (error is not null) return new(null, error);

        try
        {
            var j = JsonNode.Parse(salida!)!.AsObject();
            var filaEncabezado = (int)(Numero(j, "filaEncabezado") ?? 0);
            if (filaEncabezado != 0 && muestra.All(f => f.Numero != filaEncabezado)) filaEncabezado = 0;

            var ancho = muestra.Count == 0 ? 0 : muestra.Max(f => f.Celdas.Count);
            var columnas = new Dictionary<string, int>();
            foreach (var campo in CamposColumnas)
            {
                var letra = Cadena(j, campo);
                if (letra is null) continue;
                var indice = Indice(letra);
                if (indice >= 0 && indice < ancho && !columnas.ContainsValue(indice)) columnas[campo] = indice;
            }
            return new(new MapeoColumnasIaDto(filaEncabezado, columnas, (int)(Porcentaje(Numero(j, "confianza")) ?? 0)), null);
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            return new(null, "La IA devolvió una respuesta que no se pudo interpretar.");
        }
    }

    private static int Indice(string letra)
    {
        letra = letra.Trim().ToUpperInvariant();
        if (letra.Length is 0 or > 2 || !letra.All(c => c is >= 'A' and <= 'Z')) return -1;
        int col = 0;
        foreach (var c in letra) col = col * 26 + (c - 'A' + 1);
        return col - 1;
    }

    // ══════════════════════ Conciliación ══════════════════════

    private const string InstruccionConciliacion = """
        Eres un asistente del área comercial de Total Weight (Perú), empresa de calibración y mantenimiento de balanzas,
        básculas, pesas patrón e instrumentos. Se importa a una propuesta el listado de equipos de un cliente desde un
        Excel. Para cada fila recibes lo que dice el Excel, los equipos del inventario del cliente con serie o código
        parecido (equiposCandidatos) y modelos del catálogo de Total Weight parecidos (suministrosCandidatos).
        Reglas:
        - idEquipo: el id del equipo candidato que es EL MISMO equipo físico (la serie difiere solo por un error de
          tipeo, guiones, espacios, ceros o letras confundidas como O/0, I/1, y la marca/modelo/tipo son compatibles).
          null si ninguno es el mismo equipo. Nunca inventes ids: usa solo los de la lista de esa fila.
        - idSuministro: el id del modelo del catálogo que corresponde a la marca y modelo (o a la descripción) de la
          fila; null si ninguno corresponde. Solo ids de la lista de esa fila.
        - marca y modelo: los que se deducen del Excel (también si vienen dentro de la descripción del equipo);
          null si no se pueden deducir. No los inventes.
        - clasificacion: equipo (balanzas, básculas, tolvas, indicadores), instrumento (termómetros, manómetros,
          dinamómetros, calibradores) o pesa (pesas y juegos de pesas patrón).
        - confianza: de 0 a 100, qué tan seguro estás de idEquipo (o de idSuministro si no hay idEquipo).
        - motivo: una oración corta en español que explique la elección.
        - Devuelve una entrada por cada fila recibida, con su mismo número de fila.
        """;

    private static JsonObject EsquemaConciliacion() => Objeto(new()
    {
        ["filas"] = Lista(Objeto(new()
        {
            ["fila"]          = Tipo("NUMBER", false),
            ["idEquipo"]      = Tipo("NUMBER", true),
            ["idSuministro"]  = Tipo("NUMBER", true),
            ["marca"]         = Tipo("STRING", true),
            ["modelo"]        = Tipo("STRING", true),
            ["clasificacion"] = Enumeracion("equipo", "instrumento", "pesa"),
            ["confianza"]     = Tipo("NUMBER", false),
            ["motivo"]        = Tipo("STRING", true),
        }, ["fila", "clasificacion", "confianza"])),
    }, ["filas"]);

    public async Task<ResultadoIa<List<ConciliacionIaDto>>> ConciliarAsync(IReadOnlyList<ConsultaConciliacionIaDto> consultas, CancellationToken ct)
    {
        if (!Disponible) return new(null, "La IA no está configurada.");
        if (consultas.Count == 0) return new([], null);

        var contexto = consultas.Select(c => new
        {
            fila = c.Fila,
            excel = new
            {
                numSerie = c.Leido.NumSerie, codigoCliente = c.Leido.CodigoCliente, equipo = c.Leido.Equipo,
                marca = c.Leido.Marca, modelo = c.Leido.Modelo, capacidad = c.Leido.Capacidad,
            },
            equiposCandidatos = c.Equipos.Select(e => new
            {
                idEquipo = e.IdEquipo, numSerie = e.NumSerie, codigoCliente = e.CodigoCliente, tipo = e.ClasificacionLabel,
                marca = e.Marca, modelo = e.Modelo, alcance = e.AlcanceMaximo, sede = e.SedeNombre,
            }),
            suministrosCandidatos = c.Suministros.Select(s => new
            {
                idSuministro = s.IdSuministro, descripcion = s.Descripcion, clase = s.Clase,
                tipo = s.Tipo, subtipo = s.Subtipo, marca = s.Marca, modelo = s.Modelo,
            }),
        });
        var partes = new JsonArray
        {
            new JsonObject { ["text"] = "Filas por conciliar (JSON):\n" + JsonSerializer.Serialize(contexto, Json) },
        };

        var (salida, error) = await GenerarAsync(InstruccionConciliacion, partes, EsquemaConciliacion(), ct);
        if (error is not null) return new(null, error);

        try
        {
            var j = JsonNode.Parse(salida!)!.AsObject();
            var lista = (j["filas"] as JsonArray ?? [])
                .OfType<JsonObject>()
                .Select(f => new ConciliacionIaDto(
                    Fila:          (int)(Numero(f, "fila") ?? 0),
                    IdEquipo:      Numero(f, "idEquipo") is decimal e && e > 0 ? (long)e : null,
                    IdSuministro:  Numero(f, "idSuministro") is decimal s && s > 0 ? (long)s : null,
                    Clasificacion: Cadena(f, "clasificacion")?.ToLowerInvariant(),
                    Marca:         Recortar(Cadena(f, "marca"), 80),
                    Modelo:        Recortar(Cadena(f, "modelo"), 80),
                    Confianza:     (int)(Porcentaje(Numero(f, "confianza")) ?? 0),
                    Motivo:        Recortar(Cadena(f, "motivo"), 300)))
                .Where(f => f.Fila > 0)
                .ToList();
            return new(lista, null);
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            return new(null, "La IA devolvió una respuesta que no se pudo interpretar.");
        }
    }
}

/// <summary>Sin Gemini__ApiKey: la importación funciona solo con reglas.</summary>
public class AsistenteIaEquiposNoConfigurado : IAsistenteIaEquipos
{
    public bool   Disponible => false;
    public string Motor      => "reglas";

    public Task<ResultadoIa<MapeoColumnasIaDto>> ReconocerColumnasAsync(IReadOnlyList<FilaLeida> muestra, CancellationToken ct) =>
        Task.FromResult(new ResultadoIa<MapeoColumnasIaDto>(null, "La IA no está configurada."));

    public Task<ResultadoIa<List<ConciliacionIaDto>>> ConciliarAsync(IReadOnlyList<ConsultaConciliacionIaDto> consultas, CancellationToken ct) =>
        Task.FromResult(new ResultadoIa<List<ConciliacionIaDto>>(null, "La IA no está configurada."));
}
