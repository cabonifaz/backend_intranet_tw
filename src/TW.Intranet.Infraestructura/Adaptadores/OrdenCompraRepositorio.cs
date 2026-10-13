using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;
using MySqlConnector;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-22 — Órdenes de compra recibidas del cliente.</summary>
public class OrdenCompraRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IOrdenCompraRepositorio
{
    private static decimal Dec(MySqlDataReader r, string c) => DecimalNulo(r, c) ?? 0m;
    private static int Ent(MySqlDataReader r, string c) => (int)(DecimalNulo(r, c) ?? 0m);
    private static int? EntNulo(MySqlDataReader r, string c) => DecimalNulo(r, c) is { } v ? (int)v : null;

    public Task<RespuestaDto<PreparacionOrdenCompraDto>> PrepararAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionOrdenCompraDto>(3, "No se pudo leer la propuesta.");
                var propuesta = new PropuestaOrdenCompraDto
                {
                    IdPropuesta         = EnteroLargo(r, "id_propuesta"),
                    Numero              = Texto(r, "numero") ?? "",
                    Version             = Ent(r, "version"),
                    IdCliente           = EnteroLargo(r, "id_cliente"),
                    RazonSocial         = Texto(r, "razon_social") ?? "",
                    Ruc                 = Texto(r, "ruc"),
                    IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq            = Texto(r, "numero_rq"),
                    Total               = Dec(r, "total"),
                    IdMoneda            = Ent(r, "id_moneda"),
                    Moneda              = Texto(r, "moneda"),
                    MonedaSimbolo       = Texto(r, "moneda_simbolo"),
                    MonedaNombre        = Texto(r, "moneda_nombre"),
                    FechaAceptacion     = FechaHora(r, "fecha_aceptacion"),
                    TipoAceptacion      = Texto(r, "tipo_aceptacion"),
                    IdResponsable       = EnteroLargo(r, "id_responsable"),
                    Responsable         = Texto(r, "responsable"),
                    FechaServidor       = FechaHora(r, "fecha_servidor"),
                    VigenciaDiasDefecto = Ent(r, "vigencia_dias_defecto"),
                };

                await r.NextResultAsync(ct);
                var monedas = new List<MonedaOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    monedas.Add(new MonedaOrdenCompraDto(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "simbolo"), Texto(r, "codigo")));

                return new RespuestaDto<PreparacionOrdenCompraDto>(2, mensaje, new PreparacionOrdenCompraDto(propuesta, monedas));
            },
            ct);

    private static void Parametros(MySqlParameterCollection p, long idPropuesta, DatosOrdenCompraDto d, long idUsuario,
                                   string? ruta, string? nombre, long? tamano, string? hash, bool soloValidar)
    {
        p.AddWithValue("p_id_usuario",      idUsuario);
        p.AddWithValue("p_id_propuesta",    idPropuesta);
        p.AddWithValue("p_numero_oc",       Valor(d.NumeroOc));
        p.AddWithValue("p_fecha_oc",        Valor(d.FechaOc));
        p.AddWithValue("p_fecha_recepcion", Valor(d.FechaRecepcion));
        p.AddWithValue("p_id_moneda",       Valor(d.IdMoneda));
        p.AddWithValue("p_monto",           Valor(d.Monto));
        p.AddWithValue("p_vigencia_dias",   Valor(d.VigenciaDias));
        p.AddWithValue("p_observaciones",   Valor(d.Observaciones));
        p.AddWithValue("p_referencia",      Valor(d.Referencia));
        p.AddWithValue("p_ruta_pdf",        Valor(ruta));
        p.AddWithValue("p_nombre_pdf",      Valor(nombre));
        p.AddWithValue("p_tamano_pdf",      Valor(tamano));
        p.AddWithValue("p_hash_pdf",        Valor(hash));
        p.AddWithValue("p_solo_validar",    Bit(soloValidar));
    }

    public Task<RespuestaDto<CoberturaOrdenCompraDto>> ValidarAsync(long idPropuesta, DatosOrdenCompraDto datos, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarOrdenCompra",
            p => Parametros(p, idPropuesta, datos, idUsuario, null, null, null, null, soloValidar: true),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CoberturaOrdenCompraDto>(3, "No se pudo calcular la cobertura.");
                return new RespuestaDto<CoberturaOrdenCompraDto>(2, mensaje, new CoberturaOrdenCompraDto(
                    Texto(r, "estado_cobertura") ?? "", Dec(r, "cobertura_pct"), DecimalNulo(r, "diferencia"),
                    Dec(r, "monto_propuesta"), Ent(r, "id_moneda_propuesta"), Texto(r, "moneda_simbolo_propuesta"),
                    Dec(r, "monto_oc"), Ent(r, "id_moneda_oc"), Texto(r, "moneda_simbolo_oc")));
            },
            ct);

    public Task<RespuestaDto<OrdenCompraRegistradaDto>> RegistrarAsync(long idPropuesta, ComandoOrdenCompra c, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarOrdenCompra",
            p => Parametros(p, idPropuesta, c.Datos, idUsuario, c.RutaPdf, c.NombrePdf, c.TamanoPdf, c.HashPdf, soloValidar: false),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<OrdenCompraRegistradaDto>(3, "No se pudo leer la orden de compra registrada.");
                return new RespuestaDto<OrdenCompraRegistradaDto>(2, mensaje, new OrdenCompraRegistradaDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "",
                    Texto(r, "estado_cobertura") ?? "", Dec(r, "cobertura_pct"), DecimalNulo(r, "diferencia"),
                    FechaHora(r, "vigencia_hasta"), Texto(r, "siguiente_etapa") ?? "", Ent(r, "notificados")));
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
                    return new RespuestaDto<RutaPdfOrdenCompraDto>(1, "La orden de compra no tiene PDF adjunto.");
                return new RespuestaDto<RutaPdfOrdenCompraDto>(2, mensaje,
                    new RutaPdfOrdenCompraDto(Texto(r, "ruta") ?? "", Texto(r, "nombre_archivo") ?? "orden-compra.pdf"));
            },
            ct);

    // ══════════════════════ HU-23 — Bandeja y Detalle ══════════════════════

    public Task<RespuestaDto<BandejaOrdenesCompraDto>> ObtenerBandejaAsync(FiltrosBandejaOrdenesCompraDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaOrdenesCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_cobertura",      Valor(f.Cobertura));
                p.AddWithValue("p_id_cliente",     Valor(f.IdCliente));
                p.AddWithValue("p_id_responsable", Valor(f.IdResponsable));
                p.AddWithValue("p_fecha_desde",    Valor(f.FechaDesde));
                p.AddWithValue("p_fecha_hasta",    Valor(f.FechaHasta));
                p.AddWithValue("p_con_pdf",        f.ConPdf is { } conPdf ? Bit(conPdf) : DBNull.Value);
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
            },
            async (r, mensaje) =>
            {
                // 2. Tarjetas
                await r.NextResultAsync(ct);
                var kpis = new KpisOrdenesCompraDto(0, 0, 0, 0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    kpis = new KpisOrdenesCompraDto(
                        Ent(r, "vigentes"), Ent(r, "cobertura_parcial"), Ent(r, "saldo_insuficiente"),
                        Ent(r, "pendientes_validacion"), Ent(r, "listas_programacion"), Ent(r, "observadas"),
                        Ent(r, "vencidas"), Ent(r, "pendientes_con_alerta"));

                // 3. Filas
                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaOrdenCompraDto
                    {
                        IdOc                = EnteroLargo(r, "id_oc"),
                        NumeroOc            = Texto(r, "numero_oc") ?? "",
                        FechaOc             = Fecha(r, "fecha_oc"),
                        FechaRecepcion      = Fecha(r, "fecha_recepcion"),
                        IdCliente           = EnteroLargo(r, "id_cliente"),
                        RazonSocial         = Texto(r, "razon_social") ?? "",
                        Ruc                 = Texto(r, "ruc"),
                        IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                        NumeroRq            = Texto(r, "numero_rq"),
                        IdPropuesta         = EnteroLargoNulo(r, "id_propuesta"),
                        NumeroPropuesta     = Texto(r, "numero_propuesta"),
                        VersionPropuesta    = EntNulo(r, "version_propuesta"),
                        IdMoneda            = Ent(r, "id_moneda"),
                        Moneda              = Texto(r, "moneda"),
                        MonedaSimbolo       = Texto(r, "moneda_simbolo"),
                        MontoOc             = Dec(r, "monto_oc"),
                        MontoPropuesta      = Dec(r, "monto_propuesta"),
                        MontoAplicado       = Dec(r, "monto_aplicado"),
                        Saldo               = Dec(r, "saldo"),
                        CoberturaPct        = DecimalNulo(r, "cobertura_pct"),
                        UtilizacionPct      = Dec(r, "utilizacion_pct"),
                        CoberturaCodigo     = Texto(r, "cobertura_codigo") ?? "",
                        CoberturaProyectada = Texto(r, "cobertura_proyectada") ?? "",
                        Estado              = Texto(r, "estado") ?? "",
                        EstadoVisual        = Texto(r, "estado_visual") ?? "",
                        VigenciaHasta       = Fecha(r, "vigencia_hasta"),
                        DiasParaVencer      = EntNulo(r, "dias_para_vencer"),
                        IdResponsable       = EnteroLargo(r, "id_responsable"),
                        Responsable         = Texto(r, "responsable"),
                        TienePdf            = Booleano(r, "tiene_pdf"),
                        UrlPdf              = Texto(r, "url_pdf"),
                        ListaProgramacion   = Booleano(r, "lista_programacion"),
                        FechaRegistro       = FechaHora(r, "fecha_registro"),
                    });

                // 4. Total
                int total = await LeerTotalAsync(r, ct);

                // 5. Clientes y 6. Responsables
                var clientes     = await LeerOpcionesAsync(r, ct);
                var responsables = await LeerOpcionesAsync(r, ct);

                return new RespuestaDto<BandejaOrdenesCompraDto>(2, mensaje,
                    new BandejaOrdenesCompraDto(kpis, items, total, f.Pagina, f.PorPagina, clientes, responsables));
            },
            ct);

    private static async Task<List<OpcionFiltroDto>> LeerOpcionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<OpcionFiltroDto>();
        if (!await r.NextResultAsync(ct)) return lista;
        while (await r.ReadAsync(ct))
            lista.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return lista;
    }

    public Task<RespuestaDto<DetalleOrdenCompraDto>> ObtenerDetalleAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                // 2. Resumen
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                var resumen = new ResumenOrdenCompraDto
                {
                    IdOc                = EnteroLargo(r, "id_oc"),
                    NumeroOc            = Texto(r, "numero_oc") ?? "",
                    Referencia          = Texto(r, "referencia"),
                    Estado              = Texto(r, "estado") ?? "",
                    EstadoVisual        = Texto(r, "estado_visual") ?? "",
                    FechaOc             = Fecha(r, "fecha_oc"),
                    FechaRecepcion      = Fecha(r, "fecha_recepcion"),
                    VigenciaDesde       = Fecha(r, "vigencia_desde"),
                    VigenciaHasta       = Fecha(r, "vigencia_hasta"),
                    VigenciaDias        = EntNulo(r, "vigencia_dias"),
                    DiasParaVencer      = EntNulo(r, "dias_para_vencer"),
                    Observaciones       = Texto(r, "observaciones"),
                    IdCliente           = EnteroLargo(r, "id_cliente"),
                    RazonSocial         = Texto(r, "razon_social") ?? "",
                    Ruc                 = Texto(r, "ruc"),
                    IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq            = Texto(r, "numero_rq"),
                    ReferenciaServicio  = Texto(r, "referencia_servicio"),
                    IdPropuesta         = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta     = Texto(r, "numero_propuesta"),
                    VersionPropuesta    = EntNulo(r, "version_propuesta"),
                    IdMoneda            = Ent(r, "id_moneda"),
                    Moneda              = Texto(r, "moneda"),
                    MonedaSimbolo       = Texto(r, "moneda_simbolo"),
                    MonedaNombre        = Texto(r, "moneda_nombre"),
                    MontoOc             = Dec(r, "monto_oc"),
                    MontoPropuesta      = Dec(r, "monto_propuesta"),
                    Diferencia          = Dec(r, "diferencia"),
                    MontoAplicado       = Dec(r, "monto_aplicado"),
                    Saldo               = Dec(r, "saldo"),
                    CoberturaPct        = DecimalNulo(r, "cobertura_pct"),
                    UtilizacionPct      = Dec(r, "utilizacion_pct"),
                    CoberturaCodigo     = Texto(r, "cobertura_codigo") ?? "",
                    CoberturaProyectada = Texto(r, "cobertura_proyectada") ?? "",
                    IdResponsable       = EnteroLargo(r, "id_responsable"),
                    Responsable         = Texto(r, "responsable"),
                    IdRegistradoPor     = EnteroLargoNulo(r, "id_registrado_por"),
                    RegistradoPor       = Texto(r, "registrado_por"),
                    FechaRegistro       = FechaHora(r, "fecha_registro"),
                    IdValidadoPor       = EnteroLargoNulo(r, "id_validado_por"),
                    ValidadoPor         = Texto(r, "validado_por"),
                    FechaValidacion     = FechaHora(r, "fecha_validacion"),
                    IdMotivoObservacion = EntNulo(r, "id_motivo_observacion"),
                    MotivoObservacion   = Texto(r, "motivo_observacion"),
                    MotivosObservacion  = Texto(r, "motivos_observacion"),
                    DetalleObservacion  = Texto(r, "detalle_observacion"),
                    ResponsableCorreccion = Texto(r, "responsable_correccion"),
                    NombreArchivoPdf    = Texto(r, "nombre_archivo_pdf"),
                    TamanoPdfBytes      = EnteroLargoNulo(r, "tamano_pdf_bytes"),
                    UrlPdf              = Texto(r, "url_pdf"),
                    ListaProgramacion   = Booleano(r, "lista_programacion"),
                    OrdenesServicio     = Ent(r, "ordenes_servicio"),
                };

                // 3. Aplicaciones
                await r.NextResultAsync(ct);
                var aplicaciones = new List<AplicacionOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    aplicaciones.Add(new AplicacionOrdenCompraDto(
                        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"), Texto(r, "estado") ?? "",
                        Dec(r, "monto_propuesta"), Ent(r, "id_moneda"), Texto(r, "moneda"), Texto(r, "moneda_simbolo"),
                        DecimalNulo(r, "monto_asignado"), FechaHora(r, "fecha_asignacion"), FechaHora(r, "fecha_aceptacion"),
                        Booleano(r, "es_principal")));

                // 4. Checklist
                await r.NextResultAsync(ct);
                var checklist = new List<ItemChecklistOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    checklist.Add(new ItemChecklistOrdenCompraDto(
                        Texto(r, "codigo") ?? "", Texto(r, "descripcion") ?? "", Booleano(r, "cumple"), Texto(r, "detalle")));

                // 5. Vinculaciones
                await r.NextResultAsync(ct);
                var vinculaciones = new List<VinculacionOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    vinculaciones.Add(new VinculacionOrdenCompraDto(
                        Texto(r, "tipo") ?? "", EnteroLargoNulo(r, "id_entidad"), Texto(r, "codigo"),
                        Texto(r, "descripcion") ?? "", Texto(r, "estado"), Booleano(r, "disponible"), Texto(r, "url")));

                // 6. Documentos
                await r.NextResultAsync(ct);
                var documentos = new List<DocumentoOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    documentos.Add(new DocumentoOrdenCompraDto(
                        Texto(r, "tipo") ?? "", Texto(r, "nombre") ?? "", EnteroLargoNulo(r, "tamano_bytes"),
                        FechaHora(r, "fecha"), Texto(r, "url")));

                // 7. Workflow
                await r.NextResultAsync(ct);
                var workflow = new List<EtapaWorkflowOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    workflow.Add(new EtapaWorkflowOrdenCompraDto(
                        Ent(r, "orden"), Texto(r, "codigo") ?? "", Texto(r, "etapa") ?? "",
                        Texto(r, "estado") ?? "", FechaHora(r, "fecha")));

                // 8. Historial
                await r.NextResultAsync(ct);
                var historial = new List<EventoHistorialOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    historial.Add(new EventoHistorialOrdenCompraDto(
                        FechaHora(r, "fecha"), Texto(r, "tipo") ?? "", Texto(r, "titulo") ?? "",
                        Texto(r, "descripcion"), EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario")));

                return new RespuestaDto<DetalleOrdenCompraDto>(2, mensaje, new DetalleOrdenCompraDto(
                    resumen, aplicaciones, checklist, checklist.Count(c => c.Cumple),
                    vinculaciones, documentos, workflow, historial));
            },
            ct);

    public Task<RespuestaDto<List<PropuestaSinOrdenCompraDto>>> ObtenerPropuestasSinOrdenCompraAsync(string? busqueda, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPropuestasSinOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_busqueda",   Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<PropuestaSinOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new PropuestaSinOrdenCompraDto(
                        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"),
                        EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "ruc"),
                        EnteroLargoNulo(r, "id_requerimiento"), Texto(r, "numero_rq"),
                        Dec(r, "total"), Ent(r, "id_moneda"), Texto(r, "moneda"), Texto(r, "moneda_simbolo"),
                        FechaHora(r, "fecha_aceptacion"), EnteroLargo(r, "id_responsable"), Texto(r, "responsable")));
                return new RespuestaDto<List<PropuestaSinOrdenCompraDto>>(2, mensaje, lista);
            },
            ct);

    // ══════════════════════ HU-24 — Registro y Edición ══════════════════════

    public Task<RespuestaDto<EvaluacionOrdenCompraDto>> EvaluarAsync(long? idPropuesta, long? idOc, EvaluacionOrdenCompraSolicitudDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_EvaluarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_propuesta",  Valor(idPropuesta));
                p.AddWithValue("p_id_oc",         Valor(idOc));
                p.AddWithValue("p_numero_oc",     Valor(d.NumeroOc));
                p.AddWithValue("p_id_moneda",     Valor(d.IdMoneda));
                p.AddWithValue("p_monto",         Valor(d.Monto));
                p.AddWithValue("p_tiene_archivo", Bit(d.TieneArchivo));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<EvaluacionOrdenCompraDto>(3, "No se pudo evaluar la orden de compra.");
                var evaluacion = new EvaluacionOrdenCompraDto
                {
                    EstadoCobertura         = Texto(r, "estado_cobertura") ?? "",
                    EtiquetaCobertura       = Texto(r, "etiqueta_cobertura") ?? "",
                    CoberturaPct            = Dec(r, "cobertura_pct"),
                    Diferencia              = DecimalNulo(r, "diferencia"),
                    MontoPropuesta          = Dec(r, "monto_propuesta"),
                    IdMonedaPropuesta       = Ent(r, "id_moneda_propuesta"),
                    MonedaSimboloPropuesta  = Texto(r, "moneda_simbolo_propuesta"),
                    MontoOc                 = DecimalNulo(r, "monto_oc"),
                    IdMonedaOc              = EntNulo(r, "id_moneda_oc"),
                    MonedaSimboloOc         = Texto(r, "moneda_simbolo_oc"),
                    ToleranciaPct           = Dec(r, "tolerancia_pct"),
                    DentroTolerancia        = Booleano(r, "dentro_tolerancia"),
                    EsEdicion               = Booleano(r, "es_edicion"),
                    MontoOcActual           = DecimalNulo(r, "monto_oc_actual"),
                    IdMonedaActual          = EntNulo(r, "id_moneda_actual"),
                    CambiaMontoMoneda       = Booleano(r, "cambia_monto_moneda"),
                    RequiereRevalidacion    = Booleano(r, "requiere_revalidacion"),
                    CambioBloqueado         = Booleano(r, "cambio_bloqueado"),
                    MontoAplicadoProyectado = Dec(r, "monto_aplicado_proyectado"),
                    SaldoProyectado         = Dec(r, "saldo_proyectado"),
                };

                await r.NextResultAsync(ct);
                var checklist = new List<ItemChecklistOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    checklist.Add(new ItemChecklistOrdenCompraDto(
                        Texto(r, "codigo") ?? "", Texto(r, "descripcion") ?? "", Booleano(r, "cumple"), Texto(r, "detalle")));

                int cumplidos = checklist.Count(c => c.Cumple);
                return new RespuestaDto<EvaluacionOrdenCompraDto>(2, mensaje, evaluacion with
                {
                    Checklist          = checklist,
                    ChecklistCumplidos = cumplidos,
                    TodoConforme       = checklist.Count > 0 && cumplidos == checklist.Count,
                });
            },
            ct);

    public Task<RespuestaDto<EdicionOrdenCompraDto>> PrepararEdicionAsync(long idOc, long idUsuario, CancellationToken ct)
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
                    return new RespuestaDto<EdicionOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                var oc = new OrdenCompraEdicionDto
                {
                    IdOc                          = EnteroLargo(r, "id_oc"),
                    NumeroOc                      = Texto(r, "numero_oc") ?? "",
                    Referencia                    = Texto(r, "referencia"),
                    FechaOc                       = Fecha(r, "fecha_oc"),
                    FechaRecepcion                = Fecha(r, "fecha_recepcion"),
                    VigenciaDias                  = EntNulo(r, "vigencia_dias"),
                    VigenciaHasta                 = Fecha(r, "vigencia_hasta"),
                    IdMoneda                      = Ent(r, "id_moneda"),
                    Moneda                        = Texto(r, "moneda"),
                    MonedaSimbolo                 = Texto(r, "moneda_simbolo"),
                    MonedaNombre                  = Texto(r, "moneda_nombre"),
                    MontoOc                       = Dec(r, "monto_oc"),
                    Observaciones                 = Texto(r, "observaciones"),
                    NombreArchivoPdf              = Texto(r, "nombre_archivo_pdf"),
                    TamanoPdfBytes                = EnteroLargoNulo(r, "tamano_pdf_bytes"),
                    UrlPdf                        = Texto(r, "url_pdf"),
                    IdPropuesta                   = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta               = Texto(r, "numero_propuesta"),
                    VersionPropuesta              = EntNulo(r, "version_propuesta"),
                    IdRequerimiento               = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq                      = Texto(r, "numero_rq"),
                    IdCliente                     = EnteroLargo(r, "id_cliente"),
                    RazonSocial                   = Texto(r, "razon_social") ?? "",
                    Ruc                           = Texto(r, "ruc"),
                    IdMonedaPropuesta             = EntNulo(r, "id_moneda_propuesta"),
                    MonedaSimboloPropuesta        = Texto(r, "moneda_simbolo_propuesta"),
                    MontoPropuesta                = Dec(r, "monto_propuesta"),
                    MontoAplicado                 = Dec(r, "monto_aplicado"),
                    Saldo                         = Dec(r, "saldo"),
                    CoberturaPct                  = DecimalNulo(r, "cobertura_pct"),
                    UtilizacionPct                = Dec(r, "utilizacion_pct"),
                    CoberturaCodigo               = Texto(r, "cobertura_codigo") ?? "",
                    CoberturaProyectada           = Texto(r, "cobertura_proyectada") ?? "",
                    Estado                        = Texto(r, "estado") ?? "",
                    EstadoVisual                  = Texto(r, "estado_visual") ?? "",
                    IdMotivoObservacion           = EntNulo(r, "id_motivo_observacion"),
                    MotivoObservacion             = Texto(r, "motivo_observacion"),
                    RequiereRevalidacionAlCambiar = Booleano(r, "requiere_revalidacion_al_cambiar"),
                    PuedeCambiarMonto             = Booleano(r, "puede_cambiar_monto"),
                    OrdenesServicio               = Ent(r, "ordenes_servicio"),
                    FechaServidor                 = Fecha(r, "fecha_servidor"),
                };

                await r.NextResultAsync(ct);
                var monedas = new List<MonedaOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    monedas.Add(new MonedaOrdenCompraDto(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "simbolo"), Texto(r, "codigo")));

                return new RespuestaDto<EdicionOrdenCompraDto>(2, mensaje, new EdicionOrdenCompraDto(oc, monedas));
            },
            ct);

    public Task<RespuestaDto<OrdenCompraEditadaDto>> EditarAsync(long idOc, ComandoEdicionOrdenCompra c, bool soloValidar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_EditarOrdenCompra",
            p =>
            {
                var d = c.Datos;
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_oc",           idOc);
                p.AddWithValue("p_numero_oc",       Valor(d.NumeroOc));
                p.AddWithValue("p_referencia",      Valor(d.Referencia));
                p.AddWithValue("p_fecha_oc",        Valor(d.FechaOc));
                p.AddWithValue("p_fecha_recepcion", Valor(d.FechaRecepcion));
                p.AddWithValue("p_id_moneda",       Valor(d.IdMoneda));
                p.AddWithValue("p_monto",           Valor(d.Monto));
                p.AddWithValue("p_vigencia_dias",   Valor(d.VigenciaDias));
                p.AddWithValue("p_observaciones",   Valor(d.Observaciones));
                p.AddWithValue("p_revalidar",       Bit(c.Revalidar));
                p.AddWithValue("p_ruta_pdf",        Valor(c.RutaPdf));
                p.AddWithValue("p_nombre_pdf",      Valor(c.NombrePdf));
                p.AddWithValue("p_tamano_pdf",      Valor(c.TamanoPdf));
                p.AddWithValue("p_hash_pdf",        Valor(c.HashPdf));
                p.AddWithValue("p_solo_validar",    Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<OrdenCompraEditadaDto>(3, "No se pudo leer la orden de compra editada.");
                return new RespuestaDto<OrdenCompraEditadaDto>(2, mensaje, new OrdenCompraEditadaDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "",
                    Texto(r, "estado_cobertura") ?? "", Dec(r, "cobertura_pct"), DecimalNulo(r, "diferencia"),
                    Booleano(r, "requiere_revalidacion"), Texto(r, "cambios"), Ent(r, "notificados")));
            },
            ct);

    // ══════════════════════ HU-25 — Documento y Auditoría ══════════════════════

    private static VersionDocumentoOrdenCompraDto LeerVersion(MySqlDataReader r) => new(
        EnteroLargoNulo(r, "id_documento"), Ent(r, "version"), Texto(r, "nombre_archivo") ?? "",
        EnteroLargoNulo(r, "tamano_bytes"), Texto(r, "motivo"), Texto(r, "hash"),
        FechaHora(r, "fecha_carga"), EnteroLargoNulo(r, "id_subido_por"), Texto(r, "subido_por"),
        Booleano(r, "es_actual"), Texto(r, "url"));

    public Task<RespuestaDto<DocumentosOrdenCompraDto>> ObtenerDocumentosAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDocumentosOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DocumentosOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                long id = EnteroLargo(r, "id_oc");
                string numero = Texto(r, "numero_oc") ?? "", estado = Texto(r, "estado") ?? "";
                bool puede = Booleano(r, "puede_reemplazar");
                int total = Ent(r, "total_versiones");

                await r.NextResultAsync(ct);
                var versiones = new List<VersionDocumentoOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    versiones.Add(LeerVersion(r));

                return new RespuestaDto<DocumentosOrdenCompraDto>(2, mensaje, new DocumentosOrdenCompraDto(
                    id, numero, estado, puede, total, versiones.FirstOrDefault(v => v.EsActual), versiones));
            },
            ct);

    public Task<RespuestaDto<RutaPdfOrdenCompraDto>> ObtenerRutaVersionAsync(long idOc, long idDocumento, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerVersionDocumentoOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_oc",        idOc);
                p.AddWithValue("p_id_documento", idDocumento);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RutaPdfOrdenCompraDto>(1, "La versión del documento no existe.");
                return new RespuestaDto<RutaPdfOrdenCompraDto>(2, mensaje,
                    new RutaPdfOrdenCompraDto(Texto(r, "ruta") ?? "", Texto(r, "nombre_archivo") ?? "orden-compra.pdf"));
            },
            ct);

    public Task<RespuestaDto<DocumentoReemplazadoDto>> ReemplazarDocumentoAsync(long idOc, string? motivo, string? ruta, string? nombre,
        long? tamano, string? hash, bool soloValidar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ReemplazarDocumentoOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_oc",        idOc);
                p.AddWithValue("p_motivo",       Valor(motivo));
                p.AddWithValue("p_ruta_pdf",     Valor(ruta));
                p.AddWithValue("p_nombre_pdf",   Valor(nombre));
                p.AddWithValue("p_tamano_pdf",   Valor(tamano));
                p.AddWithValue("p_hash_pdf",     Valor(hash));
                p.AddWithValue("p_solo_validar", Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                if (soloValidar)
                    return new RespuestaDto<DocumentoReemplazadoDto>(2, mensaje);
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DocumentoReemplazadoDto>(3, "No se pudo leer la nueva versión del documento.");
                return new RespuestaDto<DocumentoReemplazadoDto>(2, mensaje, new DocumentoReemplazadoDto(
                    EnteroLargo(r, "id_documento"), Ent(r, "version"), Texto(r, "nombre_archivo"),
                    EnteroLargoNulo(r, "tamano_bytes"), Texto(r, "motivo"), Texto(r, "url")));
            },
            ct);

    public Task<RespuestaDto<AuditoriaOrdenCompraDto>> ObtenerAuditoriaAsync(long idOc, bool registrarExportacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAuditoriaOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",            idUsuario);
                p.AddWithValue("p_id_oc",                 idOc);
                p.AddWithValue("p_registrar_exportacion", Bit(registrarExportacion));
            },
            async (r, mensaje) =>
            {
                // 2. Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AuditoriaOrdenCompraDto>(3, "No se pudo leer la auditoría de la orden de compra.");
                var cabecera = new CabeceraAuditoriaOrdenCompraDto
                {
                    IdOc             = EnteroLargo(r, "id_oc"),
                    NumeroOc         = Texto(r, "numero_oc") ?? "",
                    Estado           = Texto(r, "estado") ?? "",
                    EstadoVisual     = Texto(r, "estado_visual"),
                    IdExpediente     = EnteroLargoNulo(r, "id_expediente"),
                    NumeroExpediente = Texto(r, "numero_expediente"),
                    EstadoExpediente = Texto(r, "estado_expediente"),
                    EtapaExpediente  = Texto(r, "etapa_expediente"),
                    IdPropuesta      = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta  = Texto(r, "numero_propuesta"),
                    VersionPropuesta = EntNulo(r, "version_propuesta"),
                    IdRequerimiento  = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq         = Texto(r, "numero_rq"),
                    IdCliente        = EnteroLargo(r, "id_cliente"),
                    RazonSocial      = Texto(r, "razon_social"),
                    Ruc              = Texto(r, "ruc"),
                    GeneradoEn       = FechaHora(r, "generado_en"),
                    GeneradoPor      = Texto(r, "generado_por"),
                };

                // 3. Timeline
                await r.NextResultAsync(ct);
                var timeline = new List<EventoTimelineAuditoriaDto>();
                while (await r.ReadAsync(ct))
                    timeline.Add(new EventoTimelineAuditoriaDto(
                        FechaHora(r, "fecha"), Texto(r, "codigo") ?? "", Texto(r, "titulo") ?? "", Texto(r, "descripcion"),
                        Texto(r, "nivel") ?? "info", Texto(r, "referencia"), Texto(r, "url"),
                        EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario"), Texto(r, "area"), Texto(r, "rol")));

                // 4. Registro de auditoría (CRM)
                await r.NextResultAsync(ct);
                var registro = new List<RegistroAuditoriaCrmDto>();
                while (await r.ReadAsync(ct))
                    registro.Add(new RegistroAuditoriaCrmDto(
                        FechaHora(r, "fecha"), Texto(r, "entidad") ?? "", EnteroLargo(r, "id_entidad"), Texto(r, "referencia"),
                        Texto(r, "accion") ?? "", Texto(r, "estado_anterior"), Texto(r, "estado_nuevo"),
                        Texto(r, "descripcion"), EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario")));

                // 5. Aplicaciones
                await r.NextResultAsync(ct);
                var aplicaciones = new List<AplicacionAuditoriaDto>();
                while (await r.ReadAsync(ct))
                    aplicaciones.Add(new AplicacionAuditoriaDto(
                        EnteroLargo(r, "id_propuesta"), Texto(r, "numero") ?? "", Ent(r, "version"), Texto(r, "estado") ?? "",
                        Dec(r, "monto_propuesta"), Texto(r, "moneda_simbolo"), Dec(r, "monto_asignado"),
                        FechaHora(r, "fecha_asignacion"), Texto(r, "asignado_por")));

                // 6. SSOMA
                await r.NextResultAsync(ct);
                var ssoma = new List<DocumentoSsomaAuditoriaDto>();
                while (await r.ReadAsync(ct))
                    ssoma.Add(new DocumentoSsomaAuditoriaDto(
                        Texto(r, "numero_os") ?? "", EnteroLargo(r, "id_ssoma_doc"), Texto(r, "requisito"), Texto(r, "trabajador"),
                        Texto(r, "estado") ?? "", Ent(r, "version"), FechaHora(r, "fecha_carga"),
                        Fecha(r, "fecha_vencimiento"), Texto(r, "motivo_observacion")));

                // 7. Versiones del PDF
                await r.NextResultAsync(ct);
                var versiones = new List<VersionDocumentoOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    versiones.Add(new VersionDocumentoOrdenCompraDto(
                        null, Ent(r, "version"), Texto(r, "nombre_archivo") ?? "", EnteroLargoNulo(r, "tamano_bytes"),
                        Texto(r, "motivo"), Texto(r, "hash"), FechaHora(r, "fecha_carga"), null, Texto(r, "subido_por"),
                        false, null));

                return new RespuestaDto<AuditoriaOrdenCompraDto>(2, mensaje,
                    new AuditoriaOrdenCompraDto(cabecera, timeline, registro, aplicaciones, ssoma, versiones));
            },
            ct);

    // ══════════════════════ HU-26 — Validación y Observación ══════════════════════

    public Task<RespuestaDto<PreparacionValidacionOrdenCompraDto>> PrepararValidacionAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararValidacionOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                // 2. Resumen comparativo
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionValidacionOrdenCompraDto>(3, "No se pudo leer la orden de compra.");
                var resumen = new ResumenValidacionOrdenCompraDto
                {
                    IdOc                = EnteroLargo(r, "id_oc"),
                    NumeroOc            = Texto(r, "numero_oc") ?? "",
                    Estado              = Texto(r, "estado") ?? "",
                    EstadoVisual        = Texto(r, "estado_visual") ?? "",
                    IdPropuesta         = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta     = Texto(r, "numero_propuesta"),
                    VersionPropuesta    = EntNulo(r, "version_propuesta"),
                    IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq            = Texto(r, "numero_rq"),
                    IdCliente           = EnteroLargo(r, "id_cliente"),
                    RazonSocial         = Texto(r, "razon_social"),
                    Ruc                 = Texto(r, "ruc"),
                    MontoOc             = Dec(r, "monto_oc"),
                    MontoPropuesta      = Dec(r, "monto_propuesta"),
                    IdMoneda            = Ent(r, "id_moneda"),
                    MonedaSimbolo       = Texto(r, "moneda_simbolo"),
                    MonedaNombre        = Texto(r, "moneda_nombre"),
                    CoberturaPct        = DecimalNulo(r, "cobertura_pct"),
                    CoberturaProyectada = Texto(r, "cobertura_proyectada"),
                    FechaOc             = Fecha(r, "fecha_oc"),
                    FechaRecepcion      = Fecha(r, "fecha_recepcion"),
                    VigenciaHasta       = Fecha(r, "vigencia_hasta"),
                    NombreArchivoPdf    = Texto(r, "nombre_archivo_pdf"),
                    UrlPdf              = Texto(r, "url_pdf"),
                    IdResponsable       = EnteroLargo(r, "id_responsable"),
                    Responsable         = Texto(r, "responsable"),
                    Dictamen            = Texto(r, "dictamen") ?? "",
                    DictamenMensaje     = Texto(r, "dictamen_mensaje"),
                    Inconsistencias     = Ent(r, "inconsistencias"),
                    PuedeValidar        = Booleano(r, "puede_validar"),
                    PuedeObservar       = Booleano(r, "puede_observar"),
                    MotivoNoDisponible  = Texto(r, "motivo_no_disponible"),
                };

                // 3. Checklist
                await r.NextResultAsync(ct);
                var checklist = new List<ItemValidacionOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    checklist.Add(new ItemValidacionOrdenCompraDto(
                        Ent(r, "orden"), Texto(r, "codigo") ?? "", Texto(r, "descripcion") ?? "",
                        Texto(r, "valor_sistema"), Texto(r, "valor_referencia"),
                        Booleano(r, "cumple_auto"), Booleano(r, "requiere_confirmacion"), Texto(r, "detalle")));

                // 4. Motivos (tal cual)
                await r.NextResultAsync(ct);
                var motivos = new List<OpcionFiltroDto>();
                while (await r.ReadAsync(ct))
                    motivos.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));

                // 5. Responsables de corrección
                await r.NextResultAsync(ct);
                var responsables = new List<ResponsableCorreccionDto>();
                while (await r.ReadAsync(ct))
                    responsables.Add(new ResponsableCorreccionDto(
                        EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "etiqueta") ?? "", Booleano(r, "es_responsable_propuesta")));

                // 6. Observaciones anteriores
                await r.NextResultAsync(ct);
                var observaciones = new List<ObservacionOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    observaciones.Add(new ObservacionOrdenCompraDto(
                        EnteroLargo(r, "id_observacion"), Texto(r, "estado") ?? "", Texto(r, "detalle") ?? "",
                        FechaHora(r, "fecha_observacion"), FechaHora(r, "fecha_levantamiento"),
                        Texto(r, "observado_por"), Texto(r, "responsable_correccion"), Texto(r, "motivos")));

                return new RespuestaDto<PreparacionValidacionOrdenCompraDto>(2, mensaje,
                    new PreparacionValidacionOrdenCompraDto(resumen, checklist, motivos, responsables, observaciones));
            },
            ct);

    public Task<RespuestaDto<OrdenCompraValidadaDto>> ValidarAsync(long idOc, string confirmados, string? comentario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ValidarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_oc",       idOc);
                p.AddWithValue("p_confirmados", confirmados);
                p.AddWithValue("p_comentario",  Valor(comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<OrdenCompraValidadaDto>(3, "No se pudo leer la orden de compra validada.");
                return new RespuestaDto<OrdenCompraValidadaDto>(2, mensaje, new OrdenCompraValidadaDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "",
                    Texto(r, "estado_cobertura") ?? "", FechaHora(r, "fecha_validacion"), Texto(r, "validado_por"),
                    Ent(r, "notificados")));
            },
            ct);

    public Task<RespuestaDto<ObservacionRegistradaDto>> ObservarAsync(long idOc, string motivos, string detalle, long idResponsable, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObservarOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_oc",          idOc);
                p.AddWithValue("p_motivos",        motivos);
                p.AddWithValue("p_detalle",        detalle);
                p.AddWithValue("p_id_responsable", idResponsable);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ObservacionRegistradaDto>(3, "No se pudo leer la observación registrada.");
                return new RespuestaDto<ObservacionRegistradaDto>(2, mensaje, new ObservacionRegistradaDto(
                    EnteroLargo(r, "id_observacion"), EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "",
                    Texto(r, "estado") ?? "", Texto(r, "motivos"), EnteroLargo(r, "id_responsable"), Texto(r, "responsable"),
                    Booleano(r, "expediente_bloqueado"), Ent(r, "notificados")));
            },
            ct);
}
