using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;
using MySqlConnector;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-17 / HU-18 / HU-19 / HU-20 / HU-21 — Seguimiento comercial de propuestas enviadas.</summary>
public class SeguimientoComercialRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ISeguimientoComercialRepositorio
{
    private static decimal Dec(MySqlDataReader r, string c) => DecimalNulo(r, c) ?? 0m;
    private static int Ent(MySqlDataReader r, string c) => (int)(DecimalNulo(r, c) ?? 0m);
    private static int? EntNulo(MySqlDataReader r, string c) => DecimalNulo(r, c) is { } v ? (int)v : null;

    // ── HU-17 Bandeja ─────────────────────────────────────────────────────────
    public Task<RespuestaDto<BandejaSeguimientoDto>> ObtenerBandejaAsync(FiltrosBandejaSeguimientoDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_responsable", Valor(f.IdResponsable));
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
            },
            async (r, mensaje) =>
            {
                // 2. KPIs
                await r.NextResultAsync(ct);
                var kpis = new KpisSeguimientoDto(0, 0, 0, 0, 0, 0, 0, 0, "estable", 0);
                if (await r.ReadAsync(ct))
                {
                    int rechazadas = Ent(r, "rechazadas_mes"), rechazadasAnt = Ent(r, "rechazadas_mes_anterior");
                    kpis = new KpisSeguimientoDto(
                        Ent(r, "en_seguimiento"),
                        Dec(r, "variacion_en_seguimiento_pct"),
                        Ent(r, "sin_respuesta"),
                        Ent(r, "seguimientos_vencidos"),
                        Ent(r, "aceptadas_mes"),
                        Ent(r, "meta_aceptadas_mes"),
                        rechazadas,
                        rechazadasAnt,
                        rechazadas > rechazadasAnt ? "alza" : rechazadas < rechazadasAnt ? "baja" : "estable",
                        Ent(r, "oc_pendientes"));
                }

                // 3. Filas
                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaSeguimientoDto
                    {
                        IdPropuesta            = EnteroLargo(r, "id_propuesta"),
                        Numero                 = Texto(r, "numero") ?? "",
                        Version                = Ent(r, "version"),
                        IdRequerimiento        = EnteroLargoNulo(r, "id_requerimiento"),
                        NumeroRq               = Texto(r, "numero_rq"),
                        IdCliente              = EnteroLargo(r, "id_cliente"),
                        RazonSocial            = Texto(r, "razon_social") ?? "",
                        Ruc                    = Texto(r, "ruc"),
                        IdContacto             = EnteroLargoNulo(r, "id_contacto"),
                        Contacto               = Texto(r, "contacto"),
                        CargoContacto          = Texto(r, "cargo_contacto"),
                        TelefonoContacto       = Texto(r, "telefono_contacto"),
                        CorreoContacto         = Texto(r, "correo_contacto"),
                        Total                  = Dec(r, "total"),
                        IdMoneda               = Ent(r, "id_moneda"),
                        Moneda                 = Texto(r, "moneda"),
                        MonedaSimbolo          = Texto(r, "moneda_simbolo"),
                        FechaEnvio             = FechaHora(r, "fecha_envio"),
                        DiasTranscurridos      = Ent(r, "dias_transcurridos"),
                        DiasSinRespuesta       = Ent(r, "dias_sin_respuesta"),
                        IdResponsable          = EnteroLargo(r, "id_responsable"),
                        Responsable            = Texto(r, "responsable"),
                        Interacciones          = Ent(r, "interacciones"),
                        FechaUltimaInteraccion = FechaHora(r, "fecha_ult_interaccion"),
                        CanalUltimo            = Texto(r, "canal_ult"),
                        ResultadoUltimoCodigo  = Texto(r, "resultado_ult_codigo"),
                        ResultadoUltimo        = Texto(r, "resultado_ult"),
                        ProximaAccionCodigo    = Texto(r, "proxima_accion_codigo"),
                        ProximaAccion          = Texto(r, "proxima_accion"),
                        ProximaAccionDetalle   = Texto(r, "proxima_accion_detalle"),
                        ProximaAccionFecha     = FechaHora(r, "proxima_accion_fecha"),
                        DiasParaAccion         = EntNulo(r, "dias_para_accion"),
                        HorasParaAccion        = EntNulo(r, "horas_para_accion"),
                        PrioridadAccion        = Texto(r, "prioridad_accion"),
                        PrioridadAccionCodigo  = Texto(r, "prioridad_accion_codigo"),
                        EstadoSeguimiento      = Texto(r, "estado_seguimiento") ?? "",
                        EstadoPropuesta        = Texto(r, "estado_propuesta") ?? "",
                        SlaEstado              = Texto(r, "sla_estado") ?? "",
                        SlaPct                 = EntNulo(r, "sla_pct"),
                        FechaAceptacion        = FechaHora(r, "fecha_aceptacion"),
                        FechaRechazo           = FechaHora(r, "fecha_rechazo"),
                        TieneOc                = Booleano(r, "tiene_oc"),
                        OcPorValidar           = Ent(r, "oc_por_validar"),
                    });

                // 4. Total
                int total = await LeerTotalAsync(r, ct);

                // 5. Responsables
                await r.NextResultAsync(ct);
                var responsables = new List<OpcionFiltroDto>();
                while (await r.ReadAsync(ct))
                    responsables.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? ""));

                // 6. Parámetros
                await r.NextResultAsync(ct);
                var parametros = new ParametrosSeguimientoDto(7, 48, 24, 8);
                if (await r.ReadAsync(ct))
                    parametros = new ParametrosSeguimientoDto(
                        Ent(r, "dias_sin_respuesta"), Ent(r, "sla_horas"),
                        Ent(r, "alerta_horas"), Ent(r, "meta_aceptadas_mes"));

                return new RespuestaDto<BandejaSeguimientoDto>(2, mensaje,
                    new BandejaSeguimientoDto(kpis, items, total, f.Pagina, f.PorPagina, responsables, parametros));
            },
            ct);

    // ── HU-18 Detalle ─────────────────────────────────────────────────────────
    public Task<RespuestaDto<DetalleSeguimientoDto>> ObtenerDetalleAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                // 2. Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleSeguimientoDto>(3, "No se pudo leer el detalle del seguimiento.");

                var cabecera = new CabeceraDetalleSeguimientoDto
                {
                    IdPropuesta               = EnteroLargo(r, "id_propuesta"),
                    Numero                    = Texto(r, "numero") ?? "",
                    Version                   = Ent(r, "version"),
                    IdRequerimiento           = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq                  = Texto(r, "numero_rq"),
                    IdCliente                 = EnteroLargo(r, "id_cliente"),
                    RazonSocial               = Texto(r, "razon_social") ?? "",
                    Ruc                       = Texto(r, "ruc"),
                    IdContacto                = EnteroLargoNulo(r, "id_contacto"),
                    Contacto                  = Texto(r, "contacto"),
                    CargoContacto             = Texto(r, "cargo_contacto"),
                    TelefonoContacto          = Texto(r, "telefono_contacto"),
                    CorreoContacto            = Texto(r, "correo_contacto"),
                    Total                     = Dec(r, "total"),
                    IdMoneda                  = Ent(r, "id_moneda"),
                    Moneda                    = Texto(r, "moneda"),
                    MonedaSimbolo             = Texto(r, "moneda_simbolo"),
                    FechaEnvio                = FechaHora(r, "fecha_envio"),
                    DiasTranscurridos         = Ent(r, "dias_transcurridos"),
                    DiasSinRespuesta          = Ent(r, "dias_sin_respuesta"),
                    IdResponsable             = EnteroLargo(r, "id_responsable"),
                    Responsable               = Texto(r, "responsable"),
                    Interacciones             = Ent(r, "interacciones"),
                    FechaUltimaInteraccion    = FechaHora(r, "fecha_ult_interaccion"),
                    ResultadoUltimoCodigo     = Texto(r, "resultado_ult_codigo"),
                    ResultadoUltimo           = Texto(r, "resultado_ult"),
                    ProximaAccionCodigo       = Texto(r, "proxima_accion_codigo"),
                    ProximaAccion             = Texto(r, "proxima_accion"),
                    ProximaAccionDetalle      = Texto(r, "proxima_accion_detalle"),
                    ProximaAccionFecha        = FechaHora(r, "proxima_accion_fecha"),
                    DiasParaAccion            = EntNulo(r, "dias_para_accion"),
                    HorasParaAccion           = EntNulo(r, "horas_para_accion"),
                    MinutosParaAccion         = EntNulo(r, "minutos_para_accion"),
                    IdPrioridadAccion         = EntNulo(r, "id_prioridad_accion"),
                    PrioridadAccion           = Texto(r, "prioridad_accion"),
                    PrioridadAccionCodigo     = Texto(r, "prioridad_accion_codigo"),
                    IdAsignado                = EnteroLargoNulo(r, "id_asignado"),
                    Asignado                  = Texto(r, "asignado"),
                    EstadoSeguimiento         = Texto(r, "estado_seguimiento") ?? "",
                    EstadoPropuesta           = Texto(r, "estado_propuesta") ?? "",
                    SlaEstado                 = Texto(r, "sla_estado") ?? "",
                    SlaPct                    = EntNulo(r, "sla_pct"),
                    SlaHoras                  = Ent(r, "sla_horas"),
                    FechaAceptacion           = FechaHora(r, "fecha_aceptacion"),
                    FechaRechazo              = FechaHora(r, "fecha_rechazo"),
                    TieneOc                   = Booleano(r, "tiene_oc"),
                    OcPorValidar              = Ent(r, "oc_por_validar"),
                    PuedeRegistrarSeguimiento = Booleano(r, "puede_registrar_seguimiento"),
                    PuedeEjecutarAccion       = Booleano(r, "puede_ejecutar_accion"),
                    PuedeRegistrarAceptacion  = Booleano(r, "puede_registrar_aceptacion"),
                    PuedeRegistrarRechazo     = Booleano(r, "puede_registrar_rechazo"),
                    PuedeReprogramar          = Booleano(r, "puede_reprogramar"),
                    Reprogramaciones          = Ent(r, "reprogramaciones"),
                    PuedeCerrarSinVenta       = Booleano(r, "puede_cerrar_sin_venta"),
                    PermiteReactivacion       = Booleano(r, "permite_reactivacion"),
                };

                // 3. Timeline
                await r.NextResultAsync(ct);
                var timeline = new List<EventoTimelineSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    timeline.Add(new EventoTimelineSeguimientoDto(
                        FechaHora(r, "fecha") ?? DateTime.MinValue,
                        Texto(r, "tipo") ?? "",
                        Texto(r, "titulo") ?? "",
                        Texto(r, "descripcion"),
                        Ent(r, "version"),
                        EnteroLargoNulo(r, "id_usuario"),
                        Texto(r, "usuario"),
                        Texto(r, "canal_codigo"),
                        Texto(r, "canal"),
                        Texto(r, "resultado_codigo"),
                        EnteroLargoNulo(r, "id_seguimiento"),
                        EntNulo(r, "duracion_minutos"),
                        Texto(r, "asunto"),
                        Ent(r, "adjuntos")));

                // 4. Próximas acciones
                await r.NextResultAsync(ct);
                var acciones = new List<ProximaAccionSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    acciones.Add(new ProximaAccionSeguimientoDto(
                        EnteroLargo(r, "id_seguimiento"),
                        FechaHora(r, "fecha"),
                        Texto(r, "tipo_codigo"),
                        Texto(r, "tipo") ?? "",
                        Texto(r, "detalle"),
                        EntNulo(r, "id_prioridad_accion"),
                        Texto(r, "prioridad"),
                        Texto(r, "prioridad_codigo"),
                        EnteroLargoNulo(r, "id_asignado"),
                        Texto(r, "asignado"),
                        Texto(r, "estado") ?? "",
                        FechaHora(r, "programada_en")));

                // 5. Contactos
                await r.NextResultAsync(ct);
                var contactos = new List<ContactoSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    contactos.Add(new ContactoSeguimientoDto(
                        EnteroLargo(r, "id_contacto"),
                        Texto(r, "nombres") ?? "",
                        Texto(r, "cargo"),
                        Texto(r, "area"),
                        Texto(r, "correo"),
                        Texto(r, "telefono_movil"),
                        Texto(r, "telefono_anexo"),
                        Texto(r, "estado"),
                        Ent(r, "es_contacto_principal") == 1,
                        Ent(r, "autorizado_aprobar_cotizaciones") == 1,
                        Ent(r, "es_contacto_propuesta") == 1));

                // 6. Documentos
                await r.NextResultAsync(ct);
                var documentos = new List<DocumentoSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    documentos.Add(new DocumentoSeguimientoDto(
                        Texto(r, "tipo") ?? "",
                        Texto(r, "nombre") ?? "",
                        FechaHora(r, "fecha"),
                        Ent(r, "version"),
                        Texto(r, "url"),
                        Texto(r, "estado")));

                return new RespuestaDto<DetalleSeguimientoDto>(2, mensaje,
                    new DetalleSeguimientoDto(cabecera, timeline, acciones, contactos, documentos));
            },
            ct);

    // ── HU-19 Registro ────────────────────────────────────────────────────────
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private static string SerializarDestinatarios(List<DestinatarioSeguimientoDto> lista) =>
        JsonSerializer.Serialize(lista, Json);

    private static List<DestinatarioSeguimientoDto> LeerDestinatarios(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try { return JsonSerializer.Deserialize<List<DestinatarioSeguimientoDto>>(json, Json) ?? []; }
        catch (JsonException) { return []; }
    }

    private static async Task<List<OpcionSeguimientoDto>> LeerOpcionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var lista = new List<OpcionSeguimientoDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new OpcionSeguimientoDto(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return lista;
    }

    public Task<RespuestaDto<PreparacionRegistroSeguimientoDto>> PrepararRegistroAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararRegistroSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                // 2. Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionRegistroSeguimientoDto>(3, "No se pudo leer la propuesta.");
                var cabecera = new CabeceraRegistroSeguimientoDto
                {
                    IdPropuesta             = EnteroLargo(r, "id_propuesta"),
                    Numero                  = Texto(r, "numero") ?? "",
                    Version                 = Ent(r, "version"),
                    IdCliente               = EnteroLargo(r, "id_cliente"),
                    RazonSocial             = Texto(r, "razon_social") ?? "",
                    Referencia              = Texto(r, "referencia"),
                    IdContacto              = EnteroLargoNulo(r, "id_contacto"),
                    Contacto                = Texto(r, "contacto"),
                    TelefonoContacto        = Texto(r, "telefono_contacto"),
                    CorreoContacto          = Texto(r, "correo_contacto"),
                    IdUsuario               = EnteroLargo(r, "id_usuario"),
                    Usuario                 = Texto(r, "usuario"),
                    CorreoUsuario           = Texto(r, "correo_usuario"),
                    CargoUsuario            = Texto(r, "cargo_usuario"),
                    FechaServidor           = FechaHora(r, "fecha_servidor"),
                    EstadoSeguimiento       = Texto(r, "estado_seguimiento") ?? "",
                    ProximaAccionCodigo     = Texto(r, "proxima_accion_codigo"),
                    ProximaAccion           = Texto(r, "proxima_accion"),
                    ProximaAccionFecha      = FechaHora(r, "proxima_accion_fecha"),
                    CanalSugeridoCodigo     = Texto(r, "canal_sugerido_codigo"),
                    PlantillaSugeridaCodigo = Texto(r, "plantilla_sugerida_codigo"),
                };

                // 3-4. Tipos de seguimiento y resultados
                var tipos      = await LeerOpcionesAsync(r, ct);
                var resultados = await LeerOpcionesAsync(r, ct);

                // 5. Contactos
                await r.NextResultAsync(ct);
                var contactos = new List<ContactoRegistroSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    contactos.Add(new ContactoRegistroSeguimientoDto(
                        EnteroLargo(r, "id_contacto"), Texto(r, "nombres") ?? "", Texto(r, "cargo"),
                        Texto(r, "correo"), Texto(r, "telefono_movil"), Texto(r, "telefono_anexo"),
                        Ent(r, "es_contacto_propuesta") == 1, Ent(r, "es_contacto_principal") == 1));

                // 6-7. Tipos de tarea y prioridades
                var tiposTarea  = await LeerOpcionesAsync(r, ct);
                var prioridades = await LeerOpcionesAsync(r, ct);

                // 8. Responsables
                await r.NextResultAsync(ct);
                var responsables = new List<ResponsableSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    responsables.Add(new ResponsableSeguimientoDto(
                        EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "cargo"), Ent(r, "es_usuario_actual") == 1));

                // 9. Plantillas
                await r.NextResultAsync(ct);
                var plantillas = new List<PlantillaCorreoSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    plantillas.Add(new PlantillaCorreoSeguimientoDto(
                        Ent(r, "id_plantilla"), Texto(r, "codigo") ?? "", Texto(r, "nombre") ?? "",
                        Texto(r, "asunto") ?? "", Texto(r, "cuerpo_html") ?? ""));

                // 10. Borrador
                await r.NextResultAsync(ct);
                BorradorCorreoSeguimientoDto? borrador = null;
                if (await r.ReadAsync(ct))
                    borrador = new BorradorCorreoSeguimientoDto(
                        EnteroLargo(r, "id_correo"), EntNulo(r, "id_plantilla"),
                        LeerDestinatarios(Texto(r, "para")), LeerDestinatarios(Texto(r, "cc")),
                        Texto(r, "asunto") ?? "", Texto(r, "cuerpo_html") ?? "",
                        Texto(r, "estado") ?? "", Texto(r, "error"), FechaHora(r, "fecha"));

                return new RespuestaDto<PreparacionRegistroSeguimientoDto>(2, mensaje,
                    new PreparacionRegistroSeguimientoDto(cabecera, tipos, resultados, contactos, tiposTarea,
                                                          prioridades, responsables, plantillas, borrador));
            },
            ct);

    public Task<RespuestaDto<long>> RegistrarAsync(long idPropuesta, ComandoRegistroSeguimiento c, long idUsuario,
                                                   bool soloValidar, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarSeguimiento",
            p =>
            {
                var a = c.ProximaAccion;
                p.AddWithValue("p_id_usuario",         idUsuario);
                p.AddWithValue("p_id_propuesta",       idPropuesta);
                p.AddWithValue("p_id_canal",           Valor(c.IdCanal));
                p.AddWithValue("p_canal_codigo",       Valor(c.CanalCodigo));
                p.AddWithValue("p_id_resultado",       Valor(c.IdResultado));
                p.AddWithValue("p_resultado_codigo",   Valor(c.ResultadoCodigo));
                p.AddWithValue("p_id_contacto",        Valor(c.IdContacto is > 0 ? c.IdContacto : null));
                p.AddWithValue("p_fecha_interaccion",  Valor(c.FechaInteraccion));
                p.AddWithValue("p_duracion_minutos",   Valor(c.DuracionMinutos));
                p.AddWithValue("p_notas",              Valor(c.Notas));
                p.AddWithValue("p_asunto",             Valor(c.Asunto));
                p.AddWithValue("p_programar",          Bit(c.Programar));
                p.AddWithValue("p_id_tipo_accion",     Valor(c.Programar ? a?.IdTipoAccion : null));
                p.AddWithValue("p_fecha_accion",       Valor(c.Programar ? a?.Fecha : null));
                p.AddWithValue("p_id_responsable_acc", Valor(c.Programar ? a?.IdResponsable : null));
                p.AddWithValue("p_id_prioridad",       Valor(c.Programar ? a?.IdPrioridad : null));
                p.AddWithValue("p_detalle_accion",     Valor(c.Programar ? a?.Detalle : null));
                p.AddWithValue("p_id_correo",          Valor(c.IdCorreo));
                p.AddWithValue("p_proveedor",          Valor(c.Proveedor));
                p.AddWithValue("p_id_mensaje",         Valor(c.IdMensaje));
                p.AddWithValue("p_ejecuta_accion",     Bit(c.EjecutaAccion));
                p.AddWithValue("p_solo_validar",       Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                if (soloValidar) return new RespuestaDto<long>(2, mensaje, 0);
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_seguimiento") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            },
            ct);

    public Task<RespuestaDto<CorreoSeguimientoGuardadoDto>> GuardarCorreoAsync(long idPropuesta, ComandoCorreoSeguimiento c,
        string estado, string? proveedor, string? error, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarCorreoSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
                p.AddWithValue("p_id_correo",    Valor(c.IdCorreo));
                p.AddWithValue("p_id_plantilla", Valor(c.IdPlantilla));
                p.AddWithValue("p_para",         SerializarDestinatarios(c.Para));
                p.AddWithValue("p_cc",           c.Cc.Count == 0 ? DBNull.Value : SerializarDestinatarios(c.Cc));
                p.AddWithValue("p_asunto",       c.Asunto);
                p.AddWithValue("p_cuerpo_html",  c.CuerpoHtml);
                p.AddWithValue("p_estado",       estado);
                p.AddWithValue("p_proveedor",    Valor(proveedor));
                p.AddWithValue("p_error",        Valor(error is { Length: > 500 } ? error[..500] : error));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CorreoSeguimientoGuardadoDto>(3, "No se pudo leer el correo guardado.");
                return new RespuestaDto<CorreoSeguimientoGuardadoDto>(2, mensaje, new CorreoSeguimientoGuardadoDto(
                    EnteroLargo(r, "id_correo"), Texto(r, "usuario") ?? "", Texto(r, "correo_usuario"), Texto(r, "cargo_usuario")));
            },
            ct);

    public Task<RespuestaDto<long>> RegistrarAdjuntoAsync(long idSeguimiento, string nombreArchivo, string ruta, string tipoContenido,
                                                          long tamanoBytes, long idUsuario, bool soloValidar, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarAdjuntoSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_seguimiento", idSeguimiento);
                p.AddWithValue("p_nombre_archivo", nombreArchivo);
                p.AddWithValue("p_ruta",           ruta);
                p.AddWithValue("p_tipo_contenido", tipoContenido);
                p.AddWithValue("p_tamano_bytes",   tamanoBytes);
                p.AddWithValue("p_solo_validar",   Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                if (soloValidar) return new RespuestaDto<long>(2, mensaje, 0);
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_adjunto") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            },
            ct);

    public Task<RespuestaDto<RutaAdjuntoSeguimientoDto>> ObtenerAdjuntoAsync(long idAdjunto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAdjuntoSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_adjunto", idAdjunto);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RutaAdjuntoSeguimientoDto>(1, "El adjunto no existe.");
                return new RespuestaDto<RutaAdjuntoSeguimientoDto>(2, mensaje, new RutaAdjuntoSeguimientoDto(
                    Texto(r, "ruta") ?? "", Texto(r, "nombre_archivo") ?? "adjunto",
                    Texto(r, "tipo_contenido") ?? "application/octet-stream"));
            },
            ct);

    // ── HU-20 Reprogramación ──────────────────────────────────────────────────
    public Task<RespuestaDto<PreparacionReprogramacionDto>> PrepararReprogramacionAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararReprogramacionSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                // 2. Acción actual
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionReprogramacionDto>(3, "No se pudo leer la acción actual.");
                var actual = new AccionActualSeguimientoDto
                {
                    IdPropuesta         = EnteroLargo(r, "id_propuesta"),
                    Numero              = Texto(r, "numero") ?? "",
                    Version             = Ent(r, "version"),
                    IdCliente           = EnteroLargo(r, "id_cliente"),
                    RazonSocial         = Texto(r, "razon_social") ?? "",
                    ProximaAccionCodigo = Texto(r, "proxima_accion_codigo"),
                    ProximaAccion       = Texto(r, "proxima_accion"),
                    IdTipoAccion        = EntNulo(r, "id_tipo_accion"),
                    FechaProgramada     = FechaHora(r, "fecha_programada"),
                    IdPrioridad         = EntNulo(r, "id_prioridad_accion"),
                    Prioridad           = Texto(r, "prioridad"),
                    PrioridadCodigo     = Texto(r, "prioridad_codigo"),
                    IdResponsable       = EnteroLargoNulo(r, "id_responsable_accion"),
                    Responsable         = Texto(r, "responsable_accion"),
                    Origen              = Texto(r, "origen") ?? "",
                    SlaEstado           = Texto(r, "sla_estado") ?? "",
                    EstadoSeguimiento   = Texto(r, "estado_seguimiento") ?? "",
                    Reprogramaciones    = Ent(r, "reprogramaciones"),
                    FechaServidor       = FechaHora(r, "fecha_servidor"),
                };

                // 3-4. Tipos de acción y prioridades
                var tipos       = await LeerOpcionesAsync(r, ct);
                var prioridades = await LeerOpcionesAsync(r, ct);

                // 5. Responsables
                await r.NextResultAsync(ct);
                var responsables = new List<ResponsableSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    responsables.Add(new ResponsableSeguimientoDto(
                        EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "cargo"), Ent(r, "es_usuario_actual") == 1));

                // 6. Motivos
                var motivos = await LeerOpcionesAsync(r, ct);

                // 7. Historial
                await r.NextResultAsync(ct);
                var historial = new List<ReprogramacionHistorialDto>();
                while (await r.ReadAsync(ct))
                    historial.Add(new ReprogramacionHistorialDto(
                        EnteroLargo(r, "id_reprogramacion"), FechaHora(r, "fecha"),
                        FechaHora(r, "fecha_anterior"), Texto(r, "tipo_anterior"),
                        FechaHora(r, "fecha_nueva"), Texto(r, "tipo_nuevo"),
                        Texto(r, "prioridad_nueva"), Texto(r, "responsable_nuevo"),
                        Texto(r, "motivo"), Texto(r, "motivo_codigo"), Texto(r, "detalle"), Texto(r, "usuario")));

                return new RespuestaDto<PreparacionReprogramacionDto>(2, mensaje,
                    new PreparacionReprogramacionDto(actual, tipos, prioridades, responsables, motivos, historial));
            },
            ct);

    public Task<RespuestaDto<long>> ReprogramarAccionAsync(long idPropuesta, ReprogramarAccionDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ReprogramarAccionSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_propuesta",   idPropuesta);
                p.AddWithValue("p_id_tipo_accion", Valor(dto.IdTipoAccion));
                p.AddWithValue("p_fecha_nueva",    Valor(dto.Fecha));
                p.AddWithValue("p_id_prioridad",   Valor(dto.IdPrioridad));
                p.AddWithValue("p_id_responsable", Valor(dto.IdResponsable));
                p.AddWithValue("p_id_motivo",      Valor(dto.IdMotivo));
                p.AddWithValue("p_detalle",        Valor(dto.Detalle));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_reprogramacion") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            },
            ct);

    // ── HU-21 Cierre ──────────────────────────────────────────────────────────
    public Task<RespuestaDto<PreparacionCierreSeguimientoDto>> PrepararCierreAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararCierreSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                // 2. Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionCierreSeguimientoDto>(3, "No se pudo leer la propuesta.");
                var cabecera = new CabeceraCierreSeguimientoDto
                {
                    IdPropuesta       = EnteroLargo(r, "id_propuesta"),
                    Numero            = Texto(r, "numero") ?? "",
                    Version           = Ent(r, "version"),
                    IdCliente         = EnteroLargo(r, "id_cliente"),
                    RazonSocial       = Texto(r, "razon_social") ?? "",
                    Ruc               = Texto(r, "ruc"),
                    IdRequerimiento   = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq          = Texto(r, "numero_rq"),
                    Total             = Dec(r, "total"),
                    IdMoneda          = Ent(r, "id_moneda"),
                    Moneda            = Texto(r, "moneda"),
                    MonedaSimbolo     = Texto(r, "moneda_simbolo"),
                    IdResponsable     = EnteroLargo(r, "id_responsable"),
                    Responsable       = Texto(r, "responsable"),
                    IdContacto        = EnteroLargoNulo(r, "id_contacto"),
                    Contacto          = Texto(r, "contacto"),
                    CargoContacto     = Texto(r, "cargo_contacto"),
                    EstadoSeguimiento = Texto(r, "estado_seguimiento") ?? "",
                    DiasTranscurridos = Ent(r, "dias_transcurridos"),
                    FechaServidor     = FechaHora(r, "fecha_servidor"),
                };

                // 3-5. Tipos de aceptación y motivos
                var tiposAceptacion = await LeerOpcionesAsync(r, ct);
                var motivosRechazo  = await LeerOpcionesAsync(r, ct);
                var motivosSinVenta = await LeerOpcionesAsync(r, ct);

                // 6. Contactos
                await r.NextResultAsync(ct);
                var contactos = new List<ContactoRegistroSeguimientoDto>();
                while (await r.ReadAsync(ct))
                    contactos.Add(new ContactoRegistroSeguimientoDto(
                        EnteroLargo(r, "id_contacto"), Texto(r, "nombres") ?? "", Texto(r, "cargo"),
                        Texto(r, "correo"), Texto(r, "telefono_movil"), Texto(r, "telefono_anexo"),
                        Ent(r, "es_contacto_propuesta") == 1, Ent(r, "es_contacto_principal") == 1));

                return new RespuestaDto<PreparacionCierreSeguimientoDto>(2, mensaje,
                    new PreparacionCierreSeguimientoDto(cabecera, tiposAceptacion, motivosRechazo, motivosSinVenta, contactos));
            },
            ct);

    public Task<RespuestaDto<ResultadoCierreSeguimientoDto>> CerrarAsync(long idPropuesta, ComandoCierreSeguimiento c, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CerrarSeguimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",           idUsuario);
                p.AddWithValue("p_id_propuesta",         idPropuesta);
                p.AddWithValue("p_tipo",                 c.Tipo);
                p.AddWithValue("p_id_tipo_aceptacion",   Valor(c.IdTipoAceptacion));
                p.AddWithValue("p_id_motivo",            Valor(c.IdMotivo));
                p.AddWithValue("p_id_contacto",          Valor(c.IdContacto));
                p.AddWithValue("p_fecha",                Valor(c.Fecha));
                p.AddWithValue("p_comentario",           Valor(c.Comentario));
                p.AddWithValue("p_permite_reactivacion", Bit(c.PermiteReactivacion));
                p.AddWithValue("p_confirmado",           Bit(c.Confirmado));
                p.AddWithValue("p_solo_validar",         0);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoCierreSeguimientoDto>(3, "No se pudo leer el resultado del cierre.");
                return new RespuestaDto<ResultadoCierreSeguimientoDto>(2, mensaje, new ResultadoCierreSeguimientoDto(
                    EnteroLargo(r, "id_seguimiento"), Texto(r, "estado_seguimiento") ?? "", Texto(r, "siguiente_etapa")));
            },
            ct);
}
