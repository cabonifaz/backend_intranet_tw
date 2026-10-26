using System.Text.Json;
using System.Text.Json.Nodes;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// IA de órdenes de compra con Google Gemini: lee el PDF de la OC y evalúa sus conceptos contra la propuesta.
/// La llamada HTTP, la caché y los helpers del esquema están en <see cref="GeminiClienteBase"/>.
/// </summary>
public class GeminiAsistenteOrdenCompra(HttpClient http, ConfiguracionGemini configuracion)
    : GeminiClienteBase(http, configuracion), IAsistenteIaOrdenCompra
{
    // ══════════════════════ Extracción de datos del PDF ══════════════════════

    private const string InstruccionExtraccion = """
        Eres un asistente del área comercial de Total Weight (Perú), empresa que vende servicios de calibración,
        mantenimiento e inspección de balanzas. Recibes el PDF de una ORDEN DE COMPRA emitida por un cliente a
        Total Weight. Extrae sus datos tal como aparecen en el documento.
        Reglas:
        - No inventes datos: si un dato no aparece, devuélvelo como null.
        - ruc y razonSocial son los del CLIENTE que emite la orden (no los de Total Weight, RUC 20...).
          El RUC peruano tiene 11 dígitos; devuélvelo solo con dígitos.
        - numeroPropuesta: el número de cotización/propuesta de Total Weight que menciona la OC (ej. PROP-0012-2026), si existe.
        - moneda: código ISO (PEN, USD, EUR). "S/" o "soles" = PEN; "US$" o "dólares" = USD.
        - montoTotal: el total final a pagar de la orden (con IGV si lo incluye). Números con punto decimal, sin separador de miles.
        - formaPago: el texto de la forma/condición de pago tal como figura (ej. "Crédito 30 días", "Contado").
        - condicionPagoCodigo: CONTADO, CREDITO_15, CREDITO_30, CREDITO_45, CREDITO_60, CREDITO_90 o FACTORING según la forma de pago; OTRO si es otro acuerdo; null si la OC no la indica.
        - igvIncluido: true si el total incluye IGV, false si es sin IGV, null si no se puede saber. igvPct: el porcentaje (ej. 18).
        - descuento: monto del descuento global si lo hay.
        - Fechas en formato AAAA-MM-DD. vigenciaHasta: fecha límite/vencimiento de la OC si la indica.
        - conceptos: cada línea de la orden (descripción, cantidad, precio unitario y subtotal).
        - confianza: de 0 a 100, qué tan seguro estás de la lectura en general (baja si el PDF es una imagen borrosa).
        """;

    private static JsonObject EsquemaExtraccion() => Objeto(new()
    {
        ["numeroOc"]            = Tipo("STRING", true),
        ["fechaEmision"]        = Tipo("STRING", true),
        ["ruc"]                 = Tipo("STRING", true),
        ["razonSocial"]         = Tipo("STRING", true),
        ["numeroPropuesta"]     = Tipo("STRING", true),
        ["moneda"]              = Tipo("STRING", true),
        ["montoTotal"]          = Tipo("NUMBER", true),
        ["formaPago"]           = Tipo("STRING", true),
        ["condicionPagoCodigo"] = Tipo("STRING", true),
        ["igvIncluido"]         = Tipo("BOOLEAN", true),
        ["igvPct"]              = Tipo("NUMBER", true),
        ["descuento"]           = Tipo("NUMBER", true),
        ["vigenciaHasta"]       = Tipo("STRING", true),
        ["conceptos"]           = Lista(Objeto(new()
        {
            ["descripcion"]    = Tipo("STRING", false),
            ["cantidad"]       = Tipo("NUMBER", true),
            ["precioUnitario"] = Tipo("NUMBER", true),
            ["subtotal"]       = Tipo("NUMBER", true),
        }, ["descripcion"])),
        ["confianza"]           = Tipo("NUMBER", false),
    }, ["conceptos", "confianza"]);

    public async Task<ResultadoIa<DatosExtraidosIaDto>> ExtraerAsync(byte[] pdf, CancellationToken ct)
    {
        if (!Disponible) return new(null, "La extracción con IA no está configurada (Gemini__ApiKey).");

        var partes = new JsonArray
        {
            new JsonObject { ["inlineData"] = new JsonObject { ["mimeType"] = "application/pdf", ["data"] = Convert.ToBase64String(pdf) } },
            new JsonObject { ["text"] = "Extrae los datos de esta orden de compra." },
        };
        var (texto, error) = await GenerarAsync(InstruccionExtraccion, partes, EsquemaExtraccion(), ct);
        if (error is not null) return new(null, error);

        try
        {
            var j = JsonNode.Parse(texto!)!.AsObject();
            var conceptos = new List<ConceptoOrdenCompraDto>();
            if (j["conceptos"] is JsonArray lista)
                foreach (var c in lista.OfType<JsonObject>())
                {
                    var desc = Cadena(c, "descripcion");
                    if (string.IsNullOrWhiteSpace(desc)) continue;
                    conceptos.Add(new ConceptoOrdenCompraDto
                    {
                        Descripcion    = Recortar(desc, 300)!,
                        Cantidad       = Numero(c, "cantidad"),
                        PrecioUnitario = Numero(c, "precioUnitario"),
                        Subtotal       = Numero(c, "subtotal"),
                    });
                }

            var ruc = Cadena(j, "ruc");
            if (ruc is not null)
            {
                ruc = new string(ruc.Where(char.IsDigit).ToArray());
                if (ruc.Length == 0) ruc = null;
            }

            return new(new DatosExtraidosIaDto(
                Recortar(Cadena(j, "numeroOc"), 50), FechaIso(Cadena(j, "fechaEmision")), ruc,
                Recortar(Cadena(j, "razonSocial"), 250), Recortar(Cadena(j, "numeroPropuesta"), 50),
                Cadena(j, "moneda")?.Trim().ToUpperInvariant(), Numero(j, "montoTotal"),
                Recortar(Cadena(j, "formaPago"), 150), Cadena(j, "condicionPagoCodigo")?.Trim().ToUpperInvariant(),
                Logico(j, "igvIncluido"), Numero(j, "igvPct"), Numero(j, "descuento"),
                FechaIso(Cadena(j, "vigenciaHasta")), conceptos, Porcentaje(Numero(j, "confianza"))), null);
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            return new(null, "La IA devolvió una respuesta que no se pudo interpretar.");
        }
    }

    // ══════════════════════ Evaluación de conceptos OC ↔ propuesta ══════════════════════

    private const string InstruccionEvaluacion = """
        Eres un asistente del área comercial de Total Weight (Perú). Comparas los CONCEPTOS de una orden de compra (OC)
        del cliente con los ÍTEMS de la propuesta comercial de Total Weight que la OC cubre. No decides nada:
        explicas las diferencias y sugieres qué hacer; el comercial decide.
        Reglas:
        - Empareja cada concepto de la OC con el ítem equivalente de la propuesta aunque esté redactado distinto
          (abreviaturas, orden de palabras, mayúsculas, códigos internos del cliente).
        - estado de cada concepto: coincide (mismo servicio y monto), monto_distinto (mismo servicio, monto distinto),
          falta_en_oc (ítem de la propuesta que la OC no incluye), adicional_en_oc (concepto de la OC que no está en la propuesta).
        - Si la OC cubre varias propuestas, los conceptos de la OC que correspondan a otra propuesta NO son adicionales:
          ignóralos.
        - Los ítems con opcional = true son extras que el cliente puede comprar o no: si la OC incluye uno, márcalo
          "coincide" (o "monto_distinto" si difiere el monto); si la OC no lo incluye, NO lo listes (no es falta_en_oc).
        - Las diferencias ya detectadas por las reglas (cliente, moneda, monto, forma de pago, IGV, fechas) vienen como
          contexto: no las vuelvas a calcular, solo explícalas si ayudan.
        - dictamen: 1 a 3 oraciones en español, claras y sin tecnicismos, para el comercial.
        - insights: una entrada por diferencia relevante (máximo 5), con titulo corto, explicacion y accion sugerida.
          Si "facturaIgualOc" es true y solo difieren los conceptos, la acción recomendada es "Generar nueva versión de la propuesta";
          si difieren datos que el cliente debe corregir, "Solicitar corrección al cliente".
          campo: conceptos, monto, moneda, cliente, forma_pago, igv, fecha o null.
        - Si la OC y la propuesta están en monedas distintas, los montos de la OC están en monedaOc y los de la propuesta
          en monedaPropuesta: compáralos convirtiendo con tipoCambio (soles por 1 unidad de la moneda extranjera). No
          marques monto_distinto solo por la diferencia de moneda.
        - Montos con punto decimal, sin separador de miles. confianza: de 0 a 100.
        """;

    private static JsonObject EsquemaEvaluacion() => Objeto(new()
    {
        ["conceptos"] = Lista(Objeto(new()
        {
            ["descripcion"]    = Tipo("STRING", false),
            ["montoOc"]        = Tipo("NUMBER", true),
            ["montoPropuesta"] = Tipo("NUMBER", true),
            ["estado"]         = Enumeracion("coincide", "falta_en_oc", "adicional_en_oc", "monto_distinto"),
        }, ["descripcion", "estado"])),
        ["dictamen"]  = Tipo("STRING", false),
        ["insights"]  = Lista(Objeto(new()
        {
            ["campo"]       = Tipo("STRING", true),
            ["titulo"]      = Tipo("STRING", false),
            ["explicacion"] = Tipo("STRING", false),
            ["accion"]      = Tipo("STRING", true),
            ["recomendado"] = Tipo("BOOLEAN", false),
        }, ["titulo", "explicacion", "recomendado"])),
        ["confianza"] = Tipo("NUMBER", false),
    }, ["conceptos", "dictamen", "insights", "confianza"]);

    public async Task<ResultadoIa<EvaluacionIaPropuestaDto>> EvaluarAsync(SolicitudEvaluacionIaDto s, CancellationToken ct)
    {
        if (!Disponible) return new(null, "La evaluación con IA no está configurada (Gemini__ApiKey).");

        var contexto = new
        {
            propuesta = new { numero = s.NumeroPropuesta, moneda = s.MonedaPropuestaSimbolo ?? s.MonedaSimbolo },
            monedaOc = s.MonedaSimbolo,
            monedaPropuesta = s.MonedaPropuestaSimbolo ?? s.MonedaSimbolo,
            tipoCambio = s.TipoCambio,
            facturaIgualOc = s.FacturaIgualOc,
            ocCubreVariasPropuestas = s.OcCubreVariasPropuestas,
            conceptosOc = s.ConceptosOc.Select(c => new { c.Descripcion, c.Cantidad, c.PrecioUnitario, c.Subtotal }),
            itemsPropuesta = s.ItemsPropuesta.Select(i => new { i.Descripcion, i.Alcance, i.Cantidad, i.PrecioUnitario, i.Subtotal, i.Opcional }),
            diferenciasReglas = s.Diferencias
                .Where(d => d.Severidad is "advertencia" or "critico")
                .Select(d => new { d.Campo, d.Etiqueta, d.ValorOc, d.ValorPropuesta, d.Severidad, d.Mensaje }),
        };
        var partes = new JsonArray
        {
            new JsonObject { ["text"] = "Datos a comparar (JSON):\n" + JsonSerializer.Serialize(contexto, Json) },
        };
        var (texto, error) = await GenerarAsync(InstruccionEvaluacion, partes, EsquemaEvaluacion(), ct);
        if (error is not null) return new(null, error);

        try
        {
            var j = JsonNode.Parse(texto!)!.AsObject();
            string[] estados = ["coincide", "falta_en_oc", "adicional_en_oc", "monto_distinto"];
            var conceptos = (j["conceptos"] as JsonArray ?? [])
                .OfType<JsonObject>()
                .Select(c => new ConceptoEvaluadoDto
                {
                    Descripcion    = Recortar(Cadena(c, "descripcion"), 300) ?? "",
                    MontoOc        = Numero(c, "montoOc"),
                    MontoPropuesta = Numero(c, "montoPropuesta"),
                    Estado         = estados.Contains(Cadena(c, "estado")) ? Cadena(c, "estado")! : "monto_distinto",
                })
                .Where(c => c.Descripcion.Length > 0)
                .ToList();
            var insights = (j["insights"] as JsonArray ?? [])
                .OfType<JsonObject>()
                .Take(5)
                .Select(i => new InsightIaDto
                {
                    Campo       = Recortar(Cadena(i, "campo"), 30),
                    Titulo      = Recortar(Cadena(i, "titulo"), 200) ?? "",
                    Explicacion = Recortar(Cadena(i, "explicacion"), 2000) ?? "",
                    Accion      = Recortar(Cadena(i, "accion"), 300),
                    Recomendado = Logico(i, "recomendado") ?? false,
                })
                .Where(i => i.Titulo.Length > 0)
                .ToList();

            return new(new EvaluacionIaPropuestaDto
            {
                IdPropuesta = s.IdPropuesta,
                Conceptos   = conceptos,
                Dictamen    = Recortar(Cadena(j, "dictamen"), 1000),
                Insights    = insights,
                Confianza   = Porcentaje(Numero(j, "confianza")),
                Motor       = Motor,
            }, null);
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            return new(null, "La IA devolvió una respuesta que no se pudo interpretar.");
        }
    }
}

/// <summary>Sin Gemini__ApiKey: el módulo funciona con carga manual y validación por reglas.</summary>
public class AsistenteIaOrdenCompraNoConfigurado : IAsistenteIaOrdenCompra
{
    public bool   Disponible => false;
    public string Motor      => "reglas";

    public Task<ResultadoIa<DatosExtraidosIaDto>> ExtraerAsync(byte[] pdf, CancellationToken ct) =>
        Task.FromResult(new ResultadoIa<DatosExtraidosIaDto>(null,
            "La extracción con IA no está configurada. Complete los datos de la OC manualmente."));

    public Task<ResultadoIa<EvaluacionIaPropuestaDto>> EvaluarAsync(SolicitudEvaluacionIaDto solicitud, CancellationToken ct) =>
        Task.FromResult(new ResultadoIa<EvaluacionIaPropuestaDto>(null, "La evaluación con IA no está configurada."));
}
