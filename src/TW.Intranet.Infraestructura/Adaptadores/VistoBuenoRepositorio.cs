using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;
using MySqlConnector;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-13 / HU-14 — Visto bueno de propuestas.</summary>
public class VistoBuenoRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IVistoBuenoRepositorio
{
    private static decimal Dec(MySqlDataReader r, string c) => DecimalNulo(r, c) ?? 0m;
    private static int Ent(MySqlDataReader r, string c) => (int)(DecimalNulo(r, c) ?? 0m);

    // ── HU-13 Bandeja ─────────────────────────────────────────────────────────
    public Task<RespuestaDto<BandejaVistoBuenoDto>> ObtenerBandejaAsync(FiltrosBandejaVistoBuenoDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaVistoBueno",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_comercial", Valor(f.IdComercial));
                p.AddWithValue("p_estado",       Valor(f.Estado));
                p.AddWithValue("p_id_moneda",    Valor(f.IdMoneda));
                p.AddWithValue("p_sla",          Valor(f.Sla));
                p.AddWithValue("p_dias",         f.Dias);
                p.AddWithValue("p_pagina",       f.Pagina);
                p.AddWithValue("p_por_pagina",   f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var kpis = new KpisVistoBuenoDto(0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    kpis = new KpisVistoBuenoDto(Ent(r, "pendientes"), Ent(r, "proximos_vencer"), Ent(r, "vencidos"),
                                                 Ent(r, "aprobadas_hoy"), Ent(r, "devueltas"));

                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaVistoBuenoDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaVistoBuenoDto
                    {
                        IdVb                = EnteroLargo(r, "id_vb"),
                        IdPropuesta         = EnteroLargo(r, "id_propuesta"),
                        Numero              = Texto(r, "numero") ?? "",
                        Version             = Ent(r, "version"),
                        IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                        NumeroRq            = Texto(r, "numero_rq"),
                        IdCliente           = EnteroLargo(r, "id_cliente"),
                        RazonSocial         = Texto(r, "razon_social") ?? "",
                        Ruc                 = Texto(r, "ruc"),
                        Referencia          = Texto(r, "referencia"),
                        Total               = Dec(r, "total"),
                        IdMoneda            = Ent(r, "id_moneda"),
                        Moneda              = Texto(r, "moneda"),
                        MonedaSimbolo       = Texto(r, "moneda_simbolo"),
                        DescuentoPct        = Dec(r, "descuento_pct"),
                        IdComercial         = EnteroLargo(r, "id_comercial"),
                        Comercial           = Texto(r, "comercial") ?? "",
                        IdAprobador         = EnteroLargoNulo(r, "id_aprobador"),
                        Aprobador           = Texto(r, "aprobador"),
                        AprobadorEsSuplente = Booleano(r, "aprobador_es_suplente"),
                        EstadoVb            = Texto(r, "estado_vb") ?? "",
                        FechaSolicitud      = FechaHora(r, "fecha_solicitud"),
                        FechaRespuesta      = FechaHora(r, "fecha_respuesta"),
                        VenceEn             = FechaHora(r, "vence_en"),
                        SlaHoras            = Dec(r, "sla_horas"),
                        HorasTranscurridas  = Dec(r, "horas_transcurridas"),
                        HorasRestantes      = Dec(r, "horas_restantes"),
                        SlaEstado           = Texto(r, "sla_estado") ?? "",
                        ComentarioSolicitud = Texto(r, "comentario_solicitud"),
                        ComentarioRespuesta = Texto(r, "comentario_respuesta"),
                        PuedeResolver       = Booleano(r, "puede_resolver"),
                    });

                int total = await LeerTotalAsync(r, ct);

                await r.NextResultAsync(ct);
                var comerciales = new List<OpcionFiltroDto>();
                while (await r.ReadAsync(ct))
                    comerciales.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? ""));

                await r.NextResultAsync(ct);
                var monedas = new List<OpcionFiltroDto>();
                while (await r.ReadAsync(ct))
                    monedas.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));

                await r.NextResultAsync(ct);
                var politicas = new PoliticasVistoBuenoDto(10, 10, 4, 8, 18, 25);
                if (await r.ReadAsync(ct))
                    politicas = new PoliticasVistoBuenoDto(
                        Dec(r, "descuento_aprobacion_especial_pct"), Dec(r, "margen_minimo_pct"),
                        Dec(r, "sla_horas_habiles"), Ent(r, "jornada_inicio"), Ent(r, "jornada_fin"),
                        Dec(r, "proximo_vencer_pct"));

                items = items.Select(i => i with
                {
                    RequiereAprobacionEspecial = i.DescuentoPct > politicas.DescuentoAprobacionEspecialPct
                }).ToList();

                return new RespuestaDto<BandejaVistoBuenoDto>(2, mensaje,
                    new BandejaVistoBuenoDto(kpis, items, total, f.Pagina, f.PorPagina, comerciales, monedas, politicas));
            }, ct);

    // ── Resolver (HU-13 / HU-15) ──────────────────────────────────────────────
    public Task<RespuestaDto<ResultadoResolverVistoBuenoDto>> ResolverAsync(
        long idPropuesta, ResolverVistoBuenoDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverVistoBueno",
            p =>
            {
                p.AddWithValue("p_id_propuesta",      idPropuesta);
                p.AddWithValue("p_accion",            dto.Accion);
                p.AddWithValue("p_comentario",        Valor(dto.Comentario));
                p.AddWithValue("p_validaciones",      JsonSerializer.Serialize(dto.ValidacionesConfirmadas ?? []));
                p.AddWithValue("p_id_motivo_rechazo", Valor(dto.IdMotivoRechazo));
                p.AddWithValue("p_areas",             JsonSerializer.Serialize(dto.Areas ?? []));
                p.AddWithValue("p_fecha_limite",      Valor(dto.FechaLimite));
                p.AddWithValue("p_id_usuario",        idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoResolverVistoBuenoDto>(3, "El procedimiento no devolvió el resultado.");
                return new RespuestaDto<ResultadoResolverVistoBuenoDto>(2, mensaje,
                    new ResultadoResolverVistoBuenoDto(EnteroLargo(r, "id_propuesta"),
                                                       Texto(r, "estado") ?? "", Texto(r, "estado_vb") ?? "",
                                                       EnteroLargoNulo(r, "id_correccion"),
                                                       FechaHora(r, "fecha_limite")));
            }, ct);

    // ── HU-15 Modales de decisión ─────────────────────────────────────────────
    public Task<RespuestaDto<DecisionVistoBuenoDto>> PrepararDecisionAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararDecisionVistoBueno",
            p =>
            {
                p.AddWithValue("p_id_propuesta", idPropuesta);
                p.AddWithValue("p_id_usuario",   idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DecisionVistoBuenoDto>(3, "El procedimiento no devolvió el resultado.");

                var idProp      = EnteroLargo(r, "id_propuesta");
                var numero      = Texto(r, "numero") ?? "";
                var version     = Entero(r, "version");
                var estado      = Texto(r, "estado") ?? "";
                var total       = DecimalNulo(r, "total") ?? 0;
                var simbolo     = Texto(r, "moneda_simbolo");
                var codigo      = Texto(r, "moneda_codigo");
                var cliente     = Texto(r, "cliente");
                var idComercial = EnteroLargoNulo(r, "id_comercial");
                var comercial   = Texto(r, "nombre_comercial");
                var idVb        = EnteroLargoNulo(r, "id_visto_bueno");
                var puede       = Booleano(r, "puede_resolver");
                var bloqueo     = Texto(r, "motivo_bloqueo");
                var sugerida    = FechaHora(r, "fecha_limite_sugerida");

                var validaciones = new List<ValidacionRequeridaDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    validaciones.Add(new ValidacionRequeridaDto(Texto(r, "codigo") ?? "", Texto(r, "texto") ?? "", Booleano(r, "obligatoria")));

                var motivos = new List<OpcionCatalogoVbDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    motivos.Add(new OpcionCatalogoVbDto(Entero(r, "id"), Texto(r, "nombre") ?? ""));

                var areas = new List<AreaCorreccionDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    areas.Add(new AreaCorreccionDto(Texto(r, "codigo") ?? "", Texto(r, "etiqueta") ?? ""));

                return new RespuestaDto<DecisionVistoBuenoDto>(2, mensaje, new DecisionVistoBuenoDto(
                    idProp, numero, version, estado, total, simbolo, codigo, cliente, idComercial, comercial,
                    idVb, puede, bloqueo, sugerida, validaciones, motivos, areas));
            }, ct);

    public Task<RespuestaDto<CorreccionPropuestaDto?>> ObtenerCorreccionAsync(long idPropuesta, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCorreccionPropuesta",
            p => p.AddWithValue("p_id_propuesta", idPropuesta),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CorreccionPropuestaDto?>(2, "La propuesta no tiene solicitudes de corrección.", null);

                var id          = EnteroLargo(r, "id_correccion");
                var estado      = Texto(r, "estado") ?? "";
                var obs         = Texto(r, "observaciones") ?? "";
                var limite      = FechaHora(r, "fecha_limite");
                var vencida     = Booleano(r, "vencida");
                var solEn       = FechaHora(r, "solicitado_en");
                var solPor      = Texto(r, "solicitado_por");
                var idResp      = EnteroLargoNulo(r, "id_responsable");
                var resp        = Texto(r, "nombre_responsable");
                var atendidaEn  = FechaHora(r, "atendida_en");

                var areas = new List<AreaCorreccionDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    areas.Add(new AreaCorreccionDto(Texto(r, "codigo") ?? "", Texto(r, "etiqueta") ?? ""));

                return new RespuestaDto<CorreccionPropuestaDto?>(2, mensaje,
                    new CorreccionPropuestaDto(id, estado, obs, limite, vencida, solEn, solPor, idResp, resp, atendidaEn, areas));
            }, ct);

    // ── HU-14 Validaciones ────────────────────────────────────────────────────
    public Task<RespuestaDto<(List<ValidacionPreviaDto> Validaciones, ResumenEconomicoVbDto Resumen)>> ObtenerValidacionesAsync(
        long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerValidacionesVistoBueno",
            p =>
            {
                p.AddWithValue("p_id_propuesta", idPropuesta);
                p.AddWithValue("p_id_usuario",   idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<ValidacionPreviaDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new ValidacionPreviaDto(Texto(r, "codigo") ?? "", Texto(r, "etiqueta") ?? "",
                                                      Texto(r, "nivel") ?? "", Texto(r, "detalle") ?? ""));

                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<(List<ValidacionPreviaDto>, ResumenEconomicoVbDto)>(3, "El procedimiento no devolvió el resumen.");
                var resumen = new ResumenEconomicoVbDto(
                    Ent(r, "id_moneda"), Texto(r, "moneda_simbolo"), Dec(r, "total"),
                    DecimalNulo(r, "linea_credito"), Dec(r, "credito_consumido"),
                    DecimalNulo(r, "venta_con_costo"), DecimalNulo(r, "costo"), DecimalNulo(r, "margen_pct"),
                    Dec(r, "margen_minimo_pct"), Ent(r, "items"), Ent(r, "items_sin_costo"),
                    Dec(r, "descuento_pct"), Booleano(r, "ve_costos"));

                return new RespuestaDto<(List<ValidacionPreviaDto>, ResumenEconomicoVbDto)>(2, mensaje, (lista, resumen));
            }, ct);

    // ── HU-14 Comparar versiones ──────────────────────────────────────────────
    public Task<RespuestaDto<DatosComparacionDto>> ObtenerDatosComparacionAsync(long idBase, long idDestino, CancellationToken ct)
        => EjecutarAsync("SP_CompararVersionesPropuesta",
            p =>
            {
                p.AddWithValue("p_id_base",    idBase);
                p.AddWithValue("p_id_destino", idDestino);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                CabeceraVersionDto? cBase = null, cDestino = null;
                while (await r.ReadAsync(ct))
                {
                    var c = new CabeceraVersionDto
                    {
                        IdPropuesta        = EnteroLargo(r, "id_propuesta"),
                        Numero             = Texto(r, "numero") ?? "",
                        Version            = Ent(r, "version"),
                        Estado             = Texto(r, "estado") ?? "",
                        FechaEmision       = FechaHora(r, "fecha_creacion"),
                        Referencia         = Texto(r, "referencia"),
                        TipoServicio       = Texto(r, "tipo_servicio"),
                        Cliente            = Texto(r, "razon_social"),
                        IdMoneda           = Ent(r, "id_moneda"),
                        Moneda             = Texto(r, "moneda"),
                        MonedaSimbolo      = Texto(r, "moneda_simbolo"),
                        Subtotal           = Dec(r, "subtotal"),
                        DescuentoMonto     = Dec(r, "descuento_monto"),
                        DescuentoPct       = Dec(r, "descuento_pct"),
                        IgvPct             = Dec(r, "igv_pct"),
                        IgvMonto           = Dec(r, "igv_monto"),
                        Total              = Dec(r, "total"),
                        AplicaIgv          = Booleano(r, "aplica_igv"),
                        PlazoEntregaDias   = EnteroNulo(r, "plazo_entrega_dias"),
                        VigenciaDias       = EnteroNulo(r, "vigencia_dias"),
                        CondicionPago      = Texto(r, "condicion_pago"),
                        DescripcionCambios = Texto(r, "descripcion_cambios"),
                        MotivoNuevaVersion = Texto(r, "motivo_nueva_version"),
                    };
                    if (Texto(r, "rol") == "base") cBase = c; else cDestino = c;
                }
                // Misma versión comparada consigo misma
                if (cBase is not null && cDestino is null && idBase == idDestino) cDestino = cBase;
                if (cBase is null || cDestino is null)
                    return new RespuestaDto<DatosComparacionDto>(1, "No se encontraron las versiones.");

                await r.NextResultAsync(ct);
                var items = new List<ItemVersionDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemVersionDto(Texto(r, "rol") ?? "", EnteroLargoNulo(r, "id_catalogo_item"),
                        Texto(r, "seccion") ?? "principal", Texto(r, "descripcion") ?? "",
                        Dec(r, "cantidad"), Dec(r, "precio_unitario"), Dec(r, "descuento"), Dec(r, "subtotal"),
                        Texto(r, "alcance"), Texto(r, "puntos_calibracion"), DecimalNulo(r, "frecuencia")));

                await r.NextResultAsync(ct);
                var formas = new List<FormaPagoVersionDto>();
                while (await r.ReadAsync(ct))
                    formas.Add(new FormaPagoVersionDto(Texto(r, "rol") ?? "", Dec(r, "porcentaje"), Texto(r, "condicion") ?? ""));

                await r.NextResultAsync(ct);
                var equipos = new List<EquipoVersionDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(new EquipoVersionDto(Texto(r, "rol") ?? "", EnteroLargoNulo(r, "id_equipo"),
                        Texto(r, "num_serie"), Texto(r, "codigo_tw"), Texto(r, "tipo"), Texto(r, "marca"), Texto(r, "modelo")));

                await r.NextResultAsync(ct);
                var textos = new List<TextoVersionDto>();
                while (await r.ReadAsync(ct))
                    textos.Add(new TextoVersionDto(Texto(r, "rol") ?? "", Texto(r, "seccion") ?? "", Texto(r, "texto") ?? ""));

                await r.NextResultAsync(ct);
                var versiones = new List<VersionDisponibleDto>();
                while (await r.ReadAsync(ct))
                    versiones.Add(new VersionDisponibleDto(EnteroLargo(r, "id_propuesta"), Ent(r, "version"),
                        Texto(r, "estado") ?? "", FechaHora(r, "fecha_creacion")));

                return new RespuestaDto<DatosComparacionDto>(2, mensaje,
                    new DatosComparacionDto(cBase, cDestino, items, formas, equipos, textos, versiones));
            }, ct);

    // ── Precio de costo ───────────────────────────────────────────────────────
    public Task<RespuestaDto<CostoSuministroDto>> ObtenerCostoSuministroAsync(long idSuministro, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCostoSuministro",
            p => p.AddWithValue("p_id_suministro", idSuministro),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CostoSuministroDto>(1, "Suministro no encontrado.");
                return new RespuestaDto<CostoSuministroDto>(2, mensaje, new CostoSuministroDto(
                    EnteroLargo(r, "id_suministro"), DecimalNulo(r, "precio_costo"), Ent(r, "id_moneda"),
                    Texto(r, "moneda"), DecimalNulo(r, "precio_nivel_estandar"), DecimalNulo(r, "margen_estandar_pct"),
                    FechaHora(r, "costo_actualizado_en"), Texto(r, "costo_actualizado_por")));
            }, ct);

    public Task<RespuestaDto<bool>> GuardarCostoSuministroAsync(long idSuministro, decimal? precioCosto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarCostoSuministro",
            p =>
            {
                p.AddWithValue("p_id_suministro", idSuministro);
                p.AddWithValue("p_precio_costo",  Valor(precioCosto));
                p.AddWithValue("p_id_usuario",    idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);
}
