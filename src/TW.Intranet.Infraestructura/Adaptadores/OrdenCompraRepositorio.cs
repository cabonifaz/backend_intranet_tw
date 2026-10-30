using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Órdenes de compra recibidas del cliente (Sprint 4, HU-22 a HU-28).</summary>
public class OrdenCompraRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IOrdenCompraRepositorio
{
    /// <summary>JSON en camelCase, igual que la API (los SP leen $.numeroOc, $.idMoneda…).</summary>
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private static decimal Dec(MySqlDataReader r, string c) => DecimalNulo(r, c) ?? 0m;
    private static int Ent(MySqlDataReader r, string c) => (int)(DecimalNulo(r, c) ?? 0m);
    private static int? EntNulo(MySqlDataReader r, string c) => DecimalNulo(r, c) is { } v ? (int)v : null;
    private static bool? BoolNulo(MySqlDataReader r, string c) => EsNulo(r, c) ? null : Convert.ToInt64(r[c]) != 0;

    private static object JsonParam<T>(T? valor) where T : class =>
        valor is null ? DBNull.Value : JsonSerializer.Serialize(valor, Json);

    private static T? LeerJson<T>(MySqlDataReader r, string c) where T : class
    {
        var texto = Texto(r, c);
        if (string.IsNullOrWhiteSpace(texto)) return null;
        try { return JsonSerializer.Deserialize<T>(texto, Json); }
        catch (JsonException) { return null; }
    }

    /// <summary>Valores de texto de un objeto JSON (los campos que leyó la IA), sea cual sea el tipo de cada valor.</summary>
    private static Dictionary<string, string?>? LeerCamposIa(MySqlDataReader r, string c)
    {
        var texto = Texto(r, c);
        if (string.IsNullOrWhiteSpace(texto)) return null;
        try
        {
            using var doc = JsonDocument.Parse(texto);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
            return doc.RootElement.EnumerateObject().ToDictionary(
                p => p.Name,
                p => p.Value.ValueKind switch
                {
                    JsonValueKind.Null   => null,
                    JsonValueKind.String => p.Value.GetString(),
                    _                    => p.Value.GetRawText(),
                });
        }
        catch (JsonException) { return null; }
    }

    private static async Task<List<OpcionFiltroDto>> LeerOpcionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var lista = new List<OpcionFiltroDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return lista;
    }

    private static async Task<List<MonedaOrdenCompraDto>> LeerMonedasAsync(MySqlDataReader r, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var lista = new List<MonedaOrdenCompraDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new MonedaOrdenCompraDto(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "simbolo"), Texto(r, "codigo")));
        return lista;
    }

    private static async Task<List<CondicionPagoDto>> LeerCondicionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var lista = new List<CondicionPagoDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new CondicionPagoDto(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return lista;
    }

    private static CampoComparadoOcDto LeerCampo(MySqlDataReader r, long idPropuesta) => new(
        idPropuesta, Ent(r, "orden"), Texto(r, "campo") ?? "", Texto(r, "etiqueta") ?? "",
        Texto(r, "valor_oc"), Texto(r, "valor_propuesta"), Texto(r, "severidad") ?? "sin_dato",
        Texto(r, "mensaje"), Texto(r, "accion"));

    private static PropuestaDisponibleOcDto LeerDisponible(MySqlDataReader r) => new(
        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
        TieneColumna(r, "id_cliente") ? EnteroLargoNulo(r, "id_cliente") : null,
        TieneColumna(r, "razon_social") ? Texto(r, "razon_social") : null,
        TieneColumna(r, "ruc") ? Texto(r, "ruc") : null,
        EnteroLargoNulo(r, "id_requerimiento"), Texto(r, "numero_rq"),
        EnteroLargoNulo(r, "id_contacto"), Texto(r, "contacto"),
        Dec(r, "total"), Dec(r, "saldo"), Ent(r, "id_moneda"), Texto(r, "moneda"), Texto(r, "moneda_simbolo"),
        FechaHora(r, "fecha_aceptacion"), Texto(r, "responsable"), Texto(r, "tipo_servicio"),
        TieneColumna(r, "tiene_oc") && Booleano(r, "tiene_oc"),
        TieneColumna(r, "id_oc_autogenerada") ? EnteroLargoNulo(r, "id_oc_autogenerada") : null,
        TieneColumna(r, "numero_oc_autogenerada") ? Texto(r, "numero_oc_autogenerada") : null,
        TieneColumna(r, "items") ? Ent(r, "items") : 0);

    private static bool TieneColumna(MySqlDataReader r, string c)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), c, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    // ══════════════════════ Bandeja ══════════════════════

    public Task<RespuestaDto<BandejaOrdenesCompraDto>> ObtenerBandejaAsync(FiltrosBandejaOrdenesCompraDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaOrdenesCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_id_cliente",     Valor(f.IdCliente));
                p.AddWithValue("p_id_responsable", Valor(f.IdResponsable));
                p.AddWithValue("p_id_propuesta",   Valor(f.IdPropuesta));
                p.AddWithValue("p_fecha_desde",    Valor(f.FechaDesde?.Date));
                p.AddWithValue("p_fecha_hasta",    Valor(f.FechaHasta?.Date));
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
                p.AddWithValue("p_incluir_reemplazadas", Bit(f.IncluirReemplazadas));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = new TarjetasOrdenesCompraDto(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    tarjetas = new TarjetasOrdenesCompraDto(
                        Ent(r, "total"), Ent(r, "registradas_mes"), Ent(r, "validadas"), Ent(r, "validadas_parcial"),
                        Ent(r, "observadas"), Ent(r, "parcial_u_observadas"), Ent(r, "autogeneradas_pendientes"),
                        Ent(r, "pendientes_reemplazo"), Ent(r, "sin_asignar"), Ent(r, "anuladas"));

                await r.NextResultAsync(ct);
                var montos = new List<MontoMonedaDto>();
                while (await r.ReadAsync(ct))
                    montos.Add(new MontoMonedaDto(Ent(r, "id_moneda"), Texto(r, "moneda"), Texto(r, "moneda_simbolo"), Dec(r, "monto")));

                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaOrdenCompraDto(
                        EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Booleano(r, "es_autogenerada"),
                        EnteroLargoNulo(r, "reemplazada_por"), Texto(r, "numero_oc_reemplazo"),
                        Fecha(r, "fecha_oc"), Fecha(r, "fecha_recepcion"), FechaHora(r, "fecha_registro"),
                        EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "ruc"),
                        EnteroLargoNulo(r, "id_requerimiento"), Texto(r, "numero_rq"),
                        EnteroLargoNulo(r, "id_propuesta"), Texto(r, "numero_propuesta"), EntNulo(r, "version_propuesta"),
                        Ent(r, "propuestas_vinculadas"), Ent(r, "propuestas_adicionales"),
                        Ent(r, "id_moneda"), Texto(r, "moneda"), Texto(r, "moneda_simbolo"),
                        Dec(r, "monto_oc"), Dec(r, "monto_asignado"), Dec(r, "saldo_oc"), Dec(r, "asignado_pct"),
                        Texto(r, "estado") ?? "", Texto(r, "estado_visual") ?? "", Texto(r, "resultado_ia"), Ent(r, "alertas_ia"),
                        EnteroLargoNulo(r, "id_responsable"), Texto(r, "responsable"),
                        Booleano(r, "tiene_pdf"), Texto(r, "url_pdf"), Booleano(r, "puede_anular"), Booleano(r, "puede_reemplazar")));

                var total        = await LeerTotalAsync(r, ct);
                var clientes     = await LeerOpcionesAsync(r, ct);
                var responsables = await LeerOpcionesAsync(r, ct);

                return new RespuestaDto<BandejaOrdenesCompraDto>(2, mensaje, new BandejaOrdenesCompraDto(
                    tarjetas, montos, items, total, f.Pagina, f.PorPagina, clientes, responsables));
            },
            ct);

    // ══════════════════════ Detalle ══════════════════════

    public Task<RespuestaDto<DetalleOrdenCompraDto>> ObtenerDetalleAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                var c = new CabeceraDetalleOcDto
                {
                    IdOc                    = EnteroLargo(r, "id_oc"),
                    NumeroOc                = Texto(r, "numero_oc") ?? "",
                    Estado                  = Texto(r, "estado") ?? "",
                    EstadoVisual            = Texto(r, "estado_visual") ?? "",
                    EsAutogenerada          = Booleano(r, "es_autogenerada"),
                    PendienteReemplazo      = Booleano(r, "pendiente_reemplazo"),
                    ReemplazadaPor          = EnteroLargoNulo(r, "reemplazada_por"),
                    NumeroOcReemplazo       = Texto(r, "numero_oc_reemplazo"),
                    FechaReemplazo          = FechaHora(r, "fecha_reemplazo"),
                    IdOcReemplazada         = EnteroLargoNulo(r, "id_oc_reemplazada"),
                    NumeroOcReemplazada     = Texto(r, "numero_oc_reemplazada"),
                    IdCliente               = EnteroLargo(r, "id_cliente"),
                    RazonSocial             = Texto(r, "razon_social") ?? "",
                    Ruc                     = Texto(r, "ruc"),
                    FechaRegistro           = FechaHora(r, "fecha_registro"),
                    RegistradoPor           = Texto(r, "registrado_por"),
                    IdResponsable           = EnteroLargoNulo(r, "id_responsable"),
                    Responsable             = Texto(r, "responsable"),
                    IdMoneda                = Ent(r, "id_moneda"),
                    MonedaNombre            = Texto(r, "moneda_nombre"),
                    MonedaSimbolo           = Texto(r, "moneda_simbolo"),
                    Moneda                  = Texto(r, "moneda"),
                    MontoOc                 = Dec(r, "monto_oc"),
                    PropuestasVinculadas    = Ent(r, "propuestas_vinculadas"),
                    MontoAsignado           = Dec(r, "monto_asignado"),
                    SaldoOc                 = Dec(r, "saldo_oc"),
                    AsignadoPct             = Dec(r, "asignado_pct"),
                    ResultadoIa             = Texto(r, "resultado_ia"),
                    AlertasIa               = Ent(r, "alertas_ia"),
                    VinculacionesValidadas  = Ent(r, "vinculaciones_validadas"),
                    VinculacionesObservadas = Ent(r, "vinculaciones_observadas"),
                    PendientesCorreccion    = Ent(r, "pendientes_correccion"),
                    RucClienteOc            = Texto(r, "ruc_cliente_oc"),
                    RazonSocialOc           = Texto(r, "razon_social_oc"),
                    NumeroPropuestaRef      = Texto(r, "numero_propuesta_ref"),
                    IdCondicionPago         = EntNulo(r, "id_condicion_pago"),
                    CondicionPago           = Texto(r, "condicion_pago"),
                    FormaPago               = Texto(r, "forma_pago"),
                    IgvIncluido             = BoolNulo(r, "igv_incluido"),
                    IgvPct                  = DecimalNulo(r, "igv_pct"),
                    DescuentoMonto          = DecimalNulo(r, "descuento_monto"),
                    TipoCambio              = TieneColumna(r, "tipo_cambio") ? DecimalNulo(r, "tipo_cambio") : null,
                    FechaOc                 = Fecha(r, "fecha_oc"),
                    FechaRecepcion          = Fecha(r, "fecha_recepcion"),
                    VigenciaHasta           = Fecha(r, "vigencia_hasta"),
                    FacturaIgualOc          = Booleano(r, "factura_igual_oc"),
                    Referencia              = Texto(r, "referencia"),
                    Observaciones           = Texto(r, "observaciones"),
                    Conceptos               = LeerJson<List<ConceptoOrdenCompraDto>>(r, "conceptos") ?? [],
                    CamposIa                = LeerCamposIa(r, "campos_ia"),
                    CamposManuales          = LeerJson<List<CampoCorregidoDto>>(r, "campos_manuales") ?? [],
                    TienePdf                = Booleano(r, "tiene_pdf"),
                    NombreArchivoPdf        = Texto(r, "nombre_archivo_pdf"),
                    TamanoPdfBytes          = EnteroLargoNulo(r, "tamano_pdf_bytes"),
                    UrlPdf                  = Texto(r, "url_pdf"),
                    IdMotivoAnulacion       = EntNulo(r, "id_motivo_anulacion"),
                    MotivoAnulacion         = Texto(r, "motivo_anulacion"),
                    JustificacionAnulacion  = Texto(r, "justificacion_anulacion"),
                    FechaAnulacion          = FechaHora(r, "fecha_anulacion"),
                    AnuladoPor              = Texto(r, "anulado_por"),
                    IdExpediente            = EnteroLargoNulo(r, "id_expediente"),
                    NumeroExpediente        = Texto(r, "numero_expediente"),
                    PuedeEditar             = Booleano(r, "puede_editar"),
                    PuedeReemplazarPdf      = Booleano(r, "puede_reemplazar_pdf"),
                    PuedeSubirCorregida     = Booleano(r, "puede_subir_corregida"),
                    PuedeAgregarPropuesta   = Booleano(r, "puede_agregar_propuesta"),
                    PuedeRevalidar          = Booleano(r, "puede_revalidar"),
                    PuedeAnular             = Booleano(r, "puede_anular"),
                    PuedeReemplazarAuto     = Booleano(r, "puede_reemplazar_auto"),
                    PuedeReemplazar         = Booleano(r, "puede_reemplazar"),
                };

                await r.NextResultAsync(ct);
                var propuestas = new List<PropuestaVinculadaOcDto>();
                while (await r.ReadAsync(ct))
                    propuestas.Add(new PropuestaVinculadaOcDto
                    {
                        IdPropuesta             = EnteroLargo(r, "id_propuesta"),
                        Numero                  = Texto(r, "numero") ?? "",
                        Version                 = Ent(r, "version"),
                        EstadoPropuesta         = Texto(r, "estado_propuesta"),
                        Aceptada                = Booleano(r, "aceptada"),
                        MontoPropuesta          = Dec(r, "monto_propuesta"),
                        MontoAsignado           = Dec(r, "monto_asignado"),
                        MontoCubierto           = TieneColumna(r, "monto_cubierto") ? DecimalNulo(r, "monto_cubierto") : null,
                        IdMonedaPropuesta       = TieneColumna(r, "id_moneda_propuesta") ? EntNulo(r, "id_moneda_propuesta") : null,
                        MonedaSimboloPropuesta  = TieneColumna(r, "moneda_simbolo_propuesta") ? Texto(r, "moneda_simbolo_propuesta") : null,
                        PctOc                   = Dec(r, "pct_oc"),
                        SaldoPropuesta          = Dec(r, "saldo_propuesta"),
                        IdContacto              = EnteroLargoNulo(r, "id_contacto"),
                        Contacto                = Texto(r, "contacto"),
                        CargoContacto           = Texto(r, "cargo_contacto"),
                        IdRequerimiento         = EnteroLargoNulo(r, "id_requerimiento"),
                        NumeroRq                = Texto(r, "numero_rq"),
                        Servicios               = Ent(r, "servicios"),
                        ServiciosDetalle        = Texto(r, "servicios_detalle"),
                        EstadoValidacion        = Texto(r, "estado_validacion") ?? "",
                        TipoObservacion         = Texto(r, "tipo_observacion"),
                        ResultadoIa             = Texto(r, "resultado_ia"),
                        FechaDecision           = FechaHora(r, "fecha_decision"),
                        IdValidacion            = EnteroLargoNulo(r, "id_validacion"),
                        Corrida                 = EntNulo(r, "corrida"),
                        Coincidencias           = EntNulo(r, "coincidencias"),
                        Advertencias            = EntNulo(r, "advertencias"),
                        Criticas                = EntNulo(r, "criticas"),
                        TotalCampos             = EntNulo(r, "total_campos"),
                        Sugerencia              = Texto(r, "sugerencia"),
                        Dictamen                = Texto(r, "dictamen"),
                        FechaValidacion         = FechaHora(r, "fecha_validacion"),
                        IdPropuestaNuevaVersion = EnteroLargoNulo(r, "id_propuesta_nueva_version"),
                        NumeroNuevaVersion      = Texto(r, "numero_nueva_version"),
                        VersionNuevaVersion     = EntNulo(r, "version_nueva_version"),
                        EstadoNuevaVersion      = Texto(r, "estado_nueva_version"),
                        NuevaVersionAceptada    = Booleano(r, "nueva_version_aceptada"),
                        FacturacionHabilitada   = Booleano(r, "facturacion_habilitada"),
                    });

                await r.NextResultAsync(ct);
                var diferencias = new List<CampoComparadoOcDto>();
                while (await r.ReadAsync(ct))
                    diferencias.Add(LeerCampo(r, EnteroLargo(r, "id_propuesta")));

                return new RespuestaDto<DetalleOrdenCompraDto>(2, mensaje, new DetalleOrdenCompraDto(c, propuestas, diferencias));
            },
            ct);

    // ══════════════════════ Modal de validación IA ══════════════════════

    public Task<RespuestaDto<ValidacionOrdenCompraDto>> ObtenerValidacionAsync(long idOc, long? idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerValidacionOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_oc",        idOc);
                p.AddWithValue("p_id_propuesta", Valor(idPropuesta));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ValidacionOrdenCompraDto>(3, "No se pudo leer la validación.");
                var c = new CabeceraValidacionOcDto
                {
                    IdOc                 = EnteroLargo(r, "id_oc"),
                    NumeroOc             = Texto(r, "numero_oc") ?? "",
                    FechaOc              = Fecha(r, "fecha_oc"),
                    RazonSocial          = Texto(r, "razon_social"),
                    Ruc                  = Texto(r, "ruc"),
                    NombreArchivoPdf     = Texto(r, "nombre_archivo_pdf"),
                    TamanoPdfBytes       = EnteroLargoNulo(r, "tamano_pdf_bytes"),
                    TienePdf             = Booleano(r, "tiene_pdf"),
                    IdPropuesta          = EnteroLargo(r, "id_propuesta"),
                    NumeroPropuesta      = Texto(r, "numero_propuesta") ?? "",
                    VersionPropuesta     = Ent(r, "version_propuesta"),
                    EstadoPropuesta      = Texto(r, "estado_propuesta"),
                    FechaAceptacion      = FechaHora(r, "fecha_aceptacion"),
                    NumeroExpediente     = Texto(r, "numero_expediente"),
                    EstadoValidacion     = Texto(r, "estado_validacion") ?? "",
                    TipoObservacion      = Texto(r, "tipo_observacion"),
                    IdValidacion         = EnteroLargoNulo(r, "id_validacion"),
                    Corrida              = EntNulo(r, "corrida"),
                    Origen               = Texto(r, "origen"),
                    Resultado            = Texto(r, "resultado"),
                    Coincidencias        = EntNulo(r, "coincidencias"),
                    Advertencias         = EntNulo(r, "advertencias"),
                    Criticas             = EntNulo(r, "criticas"),
                    TotalCampos          = EntNulo(r, "total_campos"),
                    ValidacionesCorridas = Ent(r, "validaciones_corridas"),
                    Dictamen             = Texto(r, "dictamen"),
                    Confianza            = DecimalNulo(r, "confianza"),
                    Motor                = Texto(r, "motor"),
                    Sugerencia           = Texto(r, "sugerencia"),
                    FechaValidacion      = FechaHora(r, "fecha_validacion"),
                };

                await r.NextResultAsync(ct);
                var campos = new List<CampoComparadoOcDto>();
                while (await r.ReadAsync(ct)) campos.Add(LeerCampo(r, c.IdPropuesta));

                await r.NextResultAsync(ct);
                var conceptos = new List<ConceptoEvaluadoDto>();
                while (await r.ReadAsync(ct))
                    conceptos.Add(new ConceptoEvaluadoDto
                    {
                        Descripcion    = Texto(r, "descripcion") ?? "",
                        MontoOc        = DecimalNulo(r, "monto_oc"),
                        MontoPropuesta = DecimalNulo(r, "monto_propuesta"),
                        Estado         = Texto(r, "estado") ?? "",
                    });

                await r.NextResultAsync(ct);
                var insights = new List<InsightIaDto>();
                while (await r.ReadAsync(ct))
                    insights.Add(new InsightIaDto
                    {
                        Campo       = Texto(r, "campo"),
                        Titulo      = Texto(r, "titulo") ?? "",
                        Explicacion = Texto(r, "explicacion") ?? "",
                        Accion      = Texto(r, "accion"),
                        Recomendado = Booleano(r, "recomendado"),
                    });

                await r.NextResultAsync(ct);
                var historial = new List<HistorialValidacionOcDto>();
                while (await r.ReadAsync(ct))
                    historial.Add(new HistorialValidacionOcDto(
                        FechaHora(r, "fecha"), Texto(r, "tipo") ?? "", Texto(r, "titulo") ?? "", Texto(r, "descripcion"),
                        Texto(r, "resultado"), EntNulo(r, "coincidencias"), EntNulo(r, "advertencias"), EntNulo(r, "criticas"),
                        Texto(r, "usuario")));

                await r.NextResultAsync(ct);
                var pills = new List<PropuestaPillOcDto>();
                while (await r.ReadAsync(ct))
                    pills.Add(new PropuestaPillOcDto(EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
                        Texto(r, "resultado_ia"), Texto(r, "estado_validacion") ?? "", Booleano(r, "seleccionada")));

                return new RespuestaDto<ValidacionOrdenCompraDto>(2, mensaje,
                    new ValidacionOrdenCompraDto(c, campos, conceptos, insights, historial, pills));
            },
            ct);

    // ══════════════════════ Timeline ══════════════════════

    public Task<RespuestaDto<TimelineOrdenCompraDto>> ObtenerTimelineAsync(long idOc, bool registrarExportacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAuditoriaOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",            idUsuario);
                p.AddWithValue("p_id_oc",                 idOc);
                p.AddWithValue("p_registrar_exportacion", Bit(registrarExportacion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<TimelineOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                var c = new CabeceraTimelineOcDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "", Texto(r, "estado_visual"),
                    Booleano(r, "es_autogenerada"), EnteroLargoNulo(r, "id_cliente"), Texto(r, "razon_social"), Texto(r, "ruc"),
                    EnteroLargoNulo(r, "id_propuesta"), Texto(r, "numero_propuesta"), EntNulo(r, "version_propuesta"),
                    FechaHora(r, "generado_en"), Texto(r, "generado_por"));

                await r.NextResultAsync(ct);
                var eventos = new List<EventoTimelineOcDto>();
                while (await r.ReadAsync(ct))
                    eventos.Add(new EventoTimelineOcDto(
                        EnteroLargo(r, "id_evento"), FechaHora(r, "fecha"), Texto(r, "accion") ?? "", Texto(r, "titulo") ?? "",
                        Texto(r, "descripcion"), Texto(r, "categoria") ?? "comercial", Texto(r, "nivel") ?? "info",
                        Texto(r, "estado_anterior"), Texto(r, "estado_nuevo"), Texto(r, "metadata"), Texto(r, "url"),
                        EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario"), Texto(r, "area"), Texto(r, "rol"),
                        Booleano(r, "automatico_ia")));

                return new RespuestaDto<TimelineOrdenCompraDto>(2, mensaje, new TimelineOrdenCompraDto(c, eventos));
            },
            ct);

    public Task<RespuestaDto<RutaPdfOrdenCompraDto>> ObtenerRutaPdfAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPdfOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RutaPdfOrdenCompraDto>(3, "No se pudo leer el PDF.");
                return new RespuestaDto<RutaPdfOrdenCompraDto>(2, mensaje,
                    new RutaPdfOrdenCompraDto(Texto(r, "ruta") ?? "", Texto(r, "nombre_archivo") ?? "orden-compra.pdf"));
            },
            ct);

    // ══════════════════════ Ficha ══════════════════════

    public Task<RespuestaDto<PreparacionOrdenCompraDto>> PrepararAsync(long idPropuesta, long? idOcReemplaza, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_propuesta",    idPropuesta);
                p.AddWithValue("p_id_oc_reemplaza", Valor(idOcReemplaza));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionOrdenCompraDto>(3, "No se pudo leer la propuesta.");
                var prop = new PropuestaOrigenOcDto(
                    EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
                    EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "ruc"),
                    EnteroLargoNulo(r, "id_requerimiento"), Texto(r, "numero_rq"),
                    EnteroLargoNulo(r, "id_contacto"), Texto(r, "contacto"), Texto(r, "cargo_contacto"),
                    Dec(r, "total"), Dec(r, "saldo"), Ent(r, "id_moneda"), Texto(r, "moneda"), Texto(r, "moneda_simbolo"),
                    EntNulo(r, "id_condicion_pago"), Texto(r, "condicion_pago"), Booleano(r, "aplica_igv"), DecimalNulo(r, "igv_pct"),
                    FechaHora(r, "fecha_expiracion"), FechaHora(r, "fecha_aceptacion"),
                    EnteroLargoNulo(r, "id_responsable"), Texto(r, "responsable"), Texto(r, "tipo_servicio"),
                    Ent(r, "items"), FechaHora(r, "fecha_servidor"));

                await r.NextResultAsync(ct);
                OcAReemplazarDto? auto = null;
                if (await r.ReadAsync(ct))
                    auto = new OcAReemplazarDto(EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Dec(r, "monto_total"),
                                                FechaHora(r, "fecha_registro"), Booleano(r, "es_autogenerada"), Texto(r, "estado") ?? "");

                await r.NextResultAsync(ct);
                var otras = new List<PropuestaDisponibleOcDto>();
                while (await r.ReadAsync(ct)) otras.Add(LeerDisponible(r));

                var monedas     = await LeerMonedasAsync(r, ct);
                var condiciones = await LeerCondicionesAsync(r, ct);

                return new RespuestaDto<PreparacionOrdenCompraDto>(2, mensaje,
                    new PreparacionOrdenCompraDto(prop, auto, otras, monedas, condiciones, false));
            },
            ct);

    public Task<RespuestaDto<PreparacionEdicionOrdenCompraDto>> PrepararEdicionAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararEdicionOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionEdicionOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                var datos = new DatosOrdenCompraDto
                {
                    NumeroOc        = Texto(r, "numero_oc"),
                    FechaEmision    = FechaHora(r, "fecha_oc"),
                    FechaRecepcion  = FechaHora(r, "fecha_recepcion"),
                    IdMoneda        = EntNulo(r, "id_moneda"),
                    MontoTotal      = DecimalNulo(r, "monto_total"),
                    IdCondicionPago = EntNulo(r, "id_condicion_pago"),
                    FormaPago       = Texto(r, "forma_pago"),
                    IgvIncluido     = BoolNulo(r, "igv_incluido"),
                    IgvPct          = DecimalNulo(r, "igv_pct"),
                    Descuento       = DecimalNulo(r, "descuento_monto"),
                    TipoCambio      = TieneColumna(r, "tipo_cambio") ? DecimalNulo(r, "tipo_cambio") : null,
                    Ruc             = Texto(r, "ruc_cliente_oc"),
                    RazonSocial     = Texto(r, "razon_social_oc"),
                    NumeroPropuesta = Texto(r, "numero_propuesta_ref"),
                    VigenciaHasta   = FechaHora(r, "vigencia_hasta"),
                    Referencia      = Texto(r, "referencia"),
                    Observaciones   = Texto(r, "observaciones"),
                    FacturaIgualOc  = Booleano(r, "factura_igual_oc"),
                    Conceptos       = LeerJson<List<ConceptoOrdenCompraDto>>(r, "conceptos") ?? [],
                    CamposIa        = LeerCamposIa(r, "campos_ia"),
                    CamposManuales  = LeerJson<List<CampoCorregidoDto>>(r, "campos_manuales") ?? [],
                };
                var oc = new OrdenCompraEdicionDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "",
                    EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "ruc"), EnteroLargoNulo(r, "id_propuesta"),
                    datos, Texto(r, "nombre_archivo_pdf"), EnteroLargoNulo(r, "tamano_pdf_bytes"), Booleano(r, "tiene_pdf"),
                    Texto(r, "url_pdf"), Booleano(r, "pendiente_correccion"), FechaHora(r, "fecha_registro"));

                await r.NextResultAsync(ct);
                var vinc = new List<VinculacionEdicionOcDto>();
                while (await r.ReadAsync(ct))
                    vinc.Add(new VinculacionEdicionOcDto(
                        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"), Dec(r, "total"), Dec(r, "saldo"),
                        Ent(r, "id_moneda"), Dec(r, "monto_asignado"), Texto(r, "estado_validacion") ?? "", Texto(r, "tipo_observacion"),
                        Texto(r, "resultado_ia"), EnteroLargoNulo(r, "id_contacto"), Texto(r, "contacto"),
                        EnteroLargoNulo(r, "id_requerimiento"), Texto(r, "numero_rq"),
                        EnteroLargoNulo(r, "id_propuesta_nueva_version"), Texto(r, "numero_nueva_version"),
                        EntNulo(r, "version_nueva_version"), Texto(r, "estado_nueva_version"), Booleano(r, "nueva_version_aceptada"),
                        TieneColumna(r, "items") ? Ent(r, "items") : 0)
                    {
                        MontoCubierto = TieneColumna(r, "monto_cubierto") ? DecimalNulo(r, "monto_cubierto") : null,
                    });

                await r.NextResultAsync(ct);
                var otras = new List<PropuestaDisponibleOcDto>();
                while (await r.ReadAsync(ct)) otras.Add(LeerDisponible(r));

                var monedas     = await LeerMonedasAsync(r, ct);
                var condiciones = await LeerCondicionesAsync(r, ct);

                return new RespuestaDto<PreparacionEdicionOrdenCompraDto>(2, mensaje,
                    new PreparacionEdicionOrdenCompraDto(oc, vinc, otras, monedas, condiciones, false));
            },
            ct);

    public Task<RespuestaDto<List<PropuestaDisponibleOcDto>>> ObtenerPropuestasDisponiblesAsync(
        long? idCliente, long? idOc, string? busqueda, bool incluirConAutogenerada, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPropuestasDisponiblesOc",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_cliente", Valor(idCliente));
                p.AddWithValue("p_id_oc",      Valor(idOc));
                p.AddWithValue("p_busqueda",   Valor(busqueda));
                p.AddWithValue("p_incluir_con_autogenerada", incluirConAutogenerada ? 1 : 0);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<PropuestaDisponibleOcDto>();
                while (await r.ReadAsync(ct)) lista.Add(LeerDisponible(r));
                return new RespuestaDto<List<PropuestaDisponibleOcDto>>(2, mensaje, lista);
            },
            ct);

    public Task<RespuestaDto<DatosIaOrdenCompraDto>> ObtenerDatosIaAsync(IReadOnlyList<long> idsPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDatosIaOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_ids_propuesta", JsonSerializer.Serialize(idsPropuesta));
            },
            async (r, mensaje) =>
            {
                var monedas     = await LeerMonedasAsync(r, ct);
                var condiciones = await LeerCondicionesAsync(r, ct);

                await r.NextResultAsync(ct);
                var items = new List<ItemPropuestaIaDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemPropuestaIaDto(EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
                        Texto(r, "descripcion") ?? "", Dec(r, "cantidad"), Dec(r, "precio_unitario"), Dec(r, "subtotal"),
                        TieneColumna(r, "alcance") ? Texto(r, "alcance") : null,
                        TieneColumna(r, "id_moneda") ? Ent(r, "id_moneda") : 0,
                        TieneColumna(r, "opcional") && Booleano(r, "opcional")));

                await r.NextResultAsync(ct);
                int? motivo = await r.ReadAsync(ct) ? EntNulo(r, "id_motivo_nueva_version") : null;

                return new RespuestaDto<DatosIaOrdenCompraDto>(2, mensaje, new DatosIaOrdenCompraDto(monedas, condiciones, items, motivo));
            },
            ct);

    // ══════════════════════ Comparar / registrar / editar ══════════════════════

    public Task<RespuestaDto<ComparacionOrdenCompraDto>> CompararAsync(CompararOrdenCompraSolicitudDto s,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CompararOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_oc",           Valor(s.IdOc));
                p.AddWithValue("p_id_propuesta",    Valor(s.IdPropuesta));
                p.AddWithValue("p_id_oc_reemplaza", Valor(s.IdOcReemplaza));
                p.AddWithValue("p_datos",           JsonParam(s.Datos));
                p.AddWithValue("p_vinculaciones",   JsonParam(s.Vinculaciones));
                p.AddWithValue("p_evaluaciones_ia", evaluaciones is { Count: > 0 } ? JsonParam(evaluaciones) : DBNull.Value);
                p.AddWithValue("p_decision",        Valor(s.Decision));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ComparacionOrdenCompraDto>(3, "No se pudo leer la validación.");
                var resumen = new ResumenComparacionOcDto(
                    Texto(r, "resultado") ?? "ok", Texto(r, "sugerencia") ?? "validar", Ent(r, "criticas"), Ent(r, "advertencias"),
                    Booleano(r, "puede_validar"), Booleano(r, "puede_observar"), Booleano(r, "puede_solicitar_correccion"),
                    Booleano(r, "puede_nueva_version"));

                await r.NextResultAsync(ct);
                var props = new List<ComparacionPropuestaOcDto>();
                while (await r.ReadAsync(ct))
                    props.Add(new ComparacionPropuestaOcDto(
                        Ent(r, "orden"), EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Dec(r, "monto_asignado"),
                        Texto(r, "resultado") ?? "ok", Ent(r, "coincidencias"), Ent(r, "advertencias"), Ent(r, "criticas"),
                        Ent(r, "total_campos"), Texto(r, "sugerencia") ?? "validar")
                    {
                        MontoCubierto = DecimalNulo(r, "monto_cubierto"),
                        IdMoneda      = Ent(r, "id_moneda"),
                        Moneda        = Texto(r, "moneda"),
                        MonedaSimbolo = Texto(r, "moneda_simbolo"),
                    });

                await r.NextResultAsync(ct);
                var campos = new List<CampoComparadoOcDto>();
                while (await r.ReadAsync(ct)) campos.Add(LeerCampo(r, EnteroLargo(r, "id_propuesta")));

                // 5. Hitos de pago por propuesta
                var hitos = new List<(long IdPropuesta, HitoPagoPropuestaDto Hito)>();
                if (await r.NextResultAsync(ct))
                    while (await r.ReadAsync(ct))
                        hitos.Add((EnteroLargo(r, "id_propuesta"),
                                   new HitoPagoPropuestaDto(Dec(r, "porcentaje"), Texto(r, "condicion") ?? "", EntNulo(r, "dias_credito"),
                                                            Texto(r, "codigo"))));
                props = props.Select(x => x with { HitosPago = hitos.Where(h => h.IdPropuesta == x.IdPropuesta).Select(h => h.Hito).ToList() })
                             .ToList();

                return new RespuestaDto<ComparacionOrdenCompraDto>(2, mensaje,
                    new ComparacionOrdenCompraDto(resumen, props, campos, evaluaciones?.ToList() ?? []));
            },
            ct);

    /// <summary>Resultado común de registrar, editar y reemplazar el PDF: 2 OC, 3 vinculaciones.</summary>
    private static async Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> LeerGuardadoAsync(
        MySqlDataReader r, string mensaje, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        if (!await r.ReadAsync(ct))
            return new RespuestaDto<ResultadoGuardarOrdenCompraDto>(3, "No se pudo leer la orden de compra guardada.");
        var oc = new OrdenCompraGuardadaDto(
            EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "", Dec(r, "monto_total"),
            EnteroLargoNulo(r, "id_oc_reemplazada"), Texto(r, "numero_oc_reemplazada"), Ent(r, "notificados"))
        {
            OcsReemplazadas = TieneColumna(r, "ocs_reemplazadas")
                ? LeerJson<List<OcReemplazadaDto>>(r, "ocs_reemplazadas") ?? []
                : [],
            TipoCambio = TieneColumna(r, "tipo_cambio") ? DecimalNulo(r, "tipo_cambio") : null,
        };

        await r.NextResultAsync(ct);
        var vinc = new List<VinculacionGuardadaOcDto>();
        while (await r.ReadAsync(ct))
            vinc.Add(new VinculacionGuardadaOcDto(
                EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"), Dec(r, "monto_asignado"),
                Texto(r, "estado_validacion") ?? "", Texto(r, "tipo_observacion"), Texto(r, "resultado_ia"),
                EnteroLargoNulo(r, "id_propuesta_nueva_version"), Texto(r, "sugerencia"),
                EntNulo(r, "coincidencias"), EntNulo(r, "advertencias"), EntNulo(r, "criticas")));

        return new RespuestaDto<ResultadoGuardarOrdenCompraDto>(2, mensaje, new ResultadoGuardarOrdenCompraDto(oc, vinc, [], null));
    }

    private static void ParametrosPdf(MySqlParameterCollection p, ArchivoPdfOcDto? pdf)
    {
        p.AddWithValue("p_ruta_pdf",   Valor(pdf?.Ruta));
        p.AddWithValue("p_nombre_pdf", Valor(pdf?.Nombre));
        p.AddWithValue("p_tamano_pdf", Valor(pdf?.Tamano));
        p.AddWithValue("p_hash_pdf",   Valor(pdf?.Hash));
    }

    public Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> RegistrarAsync(long idPropuesta, RegistrarOrdenCompraSolicitudDto s,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, ArchivoPdfOcDto pdf, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_propuesta",    idPropuesta);
                p.AddWithValue("p_id_oc_reemplaza", Valor(s.IdOcReemplaza));
                p.AddWithValue("p_datos",           JsonParam(s.Datos));
                p.AddWithValue("p_vinculaciones",   JsonParam(s.Vinculaciones));
                p.AddWithValue("p_evaluaciones_ia", evaluaciones is { Count: > 0 } ? JsonParam(evaluaciones) : DBNull.Value);
                p.AddWithValue("p_decision",        Valor(s.Decision));
                ParametrosPdf(p, pdf);
            },
            (r, mensaje) => LeerGuardadoAsync(r, mensaje, ct),
            ct);

    public Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> EditarAsync(long idOc, EditarOrdenCompraSolicitudDto s,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, ArchivoPdfOcDto? pdf, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_EditarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_oc",           idOc);
                p.AddWithValue("p_datos",           JsonParam(s.Datos));
                p.AddWithValue("p_vinculaciones",   JsonParam(s.Vinculaciones));
                p.AddWithValue("p_evaluaciones_ia", evaluaciones is { Count: > 0 } ? JsonParam(evaluaciones) : DBNull.Value);
                p.AddWithValue("p_decision",        Valor(s.Decision));
                p.AddWithValue("p_tipo_pdf",        Valor(pdf is null ? null : s.TipoPdf));
                p.AddWithValue("p_motivo_pdf",      Valor(pdf is null ? null : s.MotivoPdf));
                ParametrosPdf(p, pdf);
            },
            (r, mensaje) => LeerGuardadoAsync(r, mensaje, ct),
            ct);

    public Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> ReemplazarDocumentoAsync(long idOc, string? tipo, string? motivo,
        DatosOrdenCompraDto? datos, IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, ArchivoPdfOcDto? pdf,
        long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ReemplazarDocumentoOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_oc",           idOc);
                p.AddWithValue("p_tipo",            Valor(tipo));
                p.AddWithValue("p_motivo",          Valor(motivo));
                p.AddWithValue("p_datos",           JsonParam(datos));
                p.AddWithValue("p_evaluaciones_ia", evaluaciones is { Count: > 0 } ? JsonParam(evaluaciones) : DBNull.Value);
                ParametrosPdf(p, pdf);
                p.AddWithValue("p_solo_validar",    Bit(pdf is null));
            },
            async (r, mensaje) => pdf is null
                ? new RespuestaDto<ResultadoGuardarOrdenCompraDto>(2, mensaje)
                : await LeerGuardadoAsync(r, mensaje, ct),
            ct);

    public Task<RespuestaDto<List<RevalidacionOrdenCompraDto>>> RevalidarAsync(long idOc, long? idPropuesta,
        IReadOnlyList<EvaluacionIaPropuestaDto>? evaluaciones, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RevalidarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_oc",           idOc);
                p.AddWithValue("p_id_propuesta",    Valor(idPropuesta));
                p.AddWithValue("p_evaluaciones_ia", evaluaciones is { Count: > 0 } ? JsonParam(evaluaciones) : DBNull.Value);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<RevalidacionOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new RevalidacionOrdenCompraDto(
                        EnteroLargo(r, "id_validacion"), EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "corrida"),
                        Texto(r, "resultado") ?? "", Ent(r, "coincidencias"), Ent(r, "advertencias"), Ent(r, "criticas"),
                        Ent(r, "total_campos"), Texto(r, "sugerencia"), FechaHora(r, "fecha_validacion")));
                return new RespuestaDto<List<RevalidacionOrdenCompraDto>>(2, mensaje, lista);
            },
            ct);

    public Task<RespuestaDto<object>> VincularNuevaVersionAsync(long idOc, long idPropuesta, long idPropuestaNueva, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_VincularNuevaVersionOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",         idUsuario);
                p.AddWithValue("p_id_oc",              idOc);
                p.AddWithValue("p_id_propuesta",       idPropuesta);
                p.AddWithValue("p_id_propuesta_nueva", idPropuestaNueva);
            },
            (r, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)),
            ct);

    // ══════════════════════ Autogenerada y anulación ══════════════════════

    public Task<RespuestaDto<OcAutogeneradaDto>> AutogenerarAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AutogenerarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<OcAutogeneradaDto>(3, "No se pudo leer la OC autogenerada.");
                return new RespuestaDto<OcAutogeneradaDto>(2, mensaje, new OcAutogeneradaDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "", Dec(r, "monto_total"), Ent(r, "id_moneda")));
            },
            ct);

    public Task<RespuestaDto<PreparacionAnulacionOcDto>> PrepararAnulacionAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararAnulacionOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionAnulacionOcDto>(3, "No se pudo leer la orden de compra.");
                var impacto = new ImpactoAnulacionOcDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Booleano(r, "es_autogenerada"), Texto(r, "razon_social"),
                    Ent(r, "id_moneda"), Texto(r, "moneda_simbolo"), Dec(r, "monto_oc"), Dec(r, "monto_asignado"),
                    Ent(r, "propuestas_vinculadas"), Ent(r, "os_en_ejecucion"), Booleano(r, "impacto_critico"), FechaHora(r, "fecha_servidor"));

                await r.NextResultAsync(ct);
                var props = new List<PropuestaAfectadaOcDto>();
                while (await r.ReadAsync(ct))
                    props.Add(new PropuestaAfectadaOcDto(EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
                        Dec(r, "monto_asignado"), Texto(r, "estado_validacion"), Dec(r, "saldo_actual"), Dec(r, "saldo_despues"),
                        Booleano(r, "generara_oc_autogenerada")));

                await r.NextResultAsync(ct);
                var os = new List<OsEnEjecucionDto>();
                while (await r.ReadAsync(ct))
                    os.Add(new OsEnEjecucionDto(EnteroLargo(r, "id_os"), Texto(r, "numero") ?? "", Texto(r, "estado") ?? "",
                        FechaHora(r, "fecha_ejecucion"), Texto(r, "numero_expediente")));

                var motivos = await LeerOpcionesAsync(r, ct);
                return new RespuestaDto<PreparacionAnulacionOcDto>(2, mensaje, new PreparacionAnulacionOcDto(impacto, props, os, motivos));
            },
            ct);

    public Task<RespuestaDto<AnulacionOrdenCompraDto>> AnularAsync(long idOc, AnularOrdenCompraSolicitudDto s, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AnularOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_oc",            idOc);
                p.AddWithValue("p_id_motivo",        Valor(s.IdMotivo));
                p.AddWithValue("p_justificacion",    Valor(s.Justificacion));
                p.AddWithValue("p_confirma_impacto", Bit(s.ConfirmaImpacto));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AnulacionOrdenCompraDto>(3, "No se pudo leer la orden de compra anulada.");
                var idOcLeido = EnteroLargo(r, "id_oc");
                var numero    = Texto(r, "numero_oc") ?? "";
                var estado    = Texto(r, "estado") ?? "";
                var fecha     = FechaHora(r, "fecha_anulacion");
                var motivo    = Texto(r, "motivo");
                var just      = Texto(r, "justificacion_anulacion");

                await r.NextResultAsync(ct);
                var props = new List<PropuestaSaldoOcDto>();
                while (await r.ReadAsync(ct))
                    props.Add(new PropuestaSaldoOcDto(EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
                        Dec(r, "monto_asignado"), Dec(r, "saldo"),
                        EnteroLargoNulo(r, "id_oc_autogenerada"), Texto(r, "numero_oc_autogenerada")));

                return new RespuestaDto<AnulacionOrdenCompraDto>(2, mensaje,
                    new AnulacionOrdenCompraDto(idOcLeido, numero, estado, fecha, motivo, just, props));
            },
            ct);
}
