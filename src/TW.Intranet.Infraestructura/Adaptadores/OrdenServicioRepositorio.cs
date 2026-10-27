using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Módulo Órdenes de Servicio / Metrología (OS / OM).</summary>
public class OrdenServicioRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IOrdenServicioRepositorio
{
    private static int Ent(MySqlDataReader r, string c) => EsNulo(r, c) ? 0 : Convert.ToInt32(r[c]);

    // ══════════════════════ HU-41 Bandeja ══════════════════════

    public Task<RespuestaDto<BandejaOrdenesServicioDto>> ObtenerBandejaAsync(
        FiltrosBandejaOrdenesServicioDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaOrdenesServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_tipo",           Valor(f.Tipo));
                p.AddWithValue("p_id_cliente",     Valor(f.IdCliente));
                p.AddWithValue("p_id_responsable", Valor(f.IdResponsable));
                p.AddWithValue("p_fecha_desde",    Valor(f.FechaDesde?.Date));
                p.AddWithValue("p_fecha_hasta",    Valor(f.FechaHasta?.Date));
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
                p.AddWithValue("p_exportar",       Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = new TarjetasOrdenesServicioDto(0, 0, 0, 0, 0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    tarjetas = new TarjetasOrdenesServicioDto(
                        Ent(r, "total"), Ent(r, "borradores"), Ent(r, "emitidas"), Ent(r, "emitidas_semana"),
                        Ent(r, "programadas"), Ent(r, "en_ejecucion"), Ent(r, "finalizadas"), Ent(r, "finalizadas_mes"),
                        Ent(r, "anuladas"));

                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaOrdenServicioDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaOrdenServicioDto
                    {
                        IdOs                   = EnteroLargo(r, "id_os"),
                        Tipo                   = Texto(r, "tipo") ?? "OS",
                        Numero                 = Texto(r, "numero") ?? "",
                        Estado                 = Texto(r, "estado") ?? "",
                        EstadoGrupo            = Texto(r, "estado_grupo") ?? "",
                        EstadoLabel            = Texto(r, "estado_label") ?? "",
                        FechaEmision           = FechaHora(r, "fecha_emision"),
                        Emitida                = Booleano(r, "emitida_registrada"),
                        IdCliente              = EnteroLargoNulo(r, "id_cliente"),
                        RazonSocial            = Texto(r, "razon_social"),
                        Ruc                    = Texto(r, "ruc"),
                        IdPropuesta            = EnteroLargoNulo(r, "id_propuesta"),
                        NumeroPropuesta        = Texto(r, "numero_propuesta"),
                        VersionPropuesta       = EnteroNulo(r, "version_propuesta"),
                        IdExpediente           = EnteroLargoNulo(r, "id_expediente"),
                        IdResponsable          = EnteroLargoNulo(r, "id_responsable"),
                        Responsable            = Texto(r, "responsable"),
                        NumeroEquipos          = Ent(r, "n_equipos"),
                        NumeroConceptos        = Ent(r, "n_conceptos"),
                        SolicitudPendiente     = Booleano(r, "solicitud_pendiente"),
                        IdSolicitudPendiente   = EnteroLargoNulo(r, "id_solicitud_pendiente"),
                        EdicionAprobada        = Booleano(r, "edicion_aprobada"),
                        PuedeEditar            = Booleano(r, "puede_editar"),
                        PuedeSolicitarEdicion  = Booleano(r, "puede_solicitar_edicion"),
                        PuedeResolverSolicitud = Booleano(r, "puede_resolver_solicitud"),
                        PuedeAnular            = Booleano(r, "puede_anular"),
                    });

                await r.NextResultAsync(ct);
                var total = await r.ReadAsync(ct) ? Ent(r, "total") : 0;

                var clientes = await LeerOpcionesAsync(r, ct);
                var responsables = await LeerOpcionesAsync(r, ct);

                return new RespuestaDto<BandejaOrdenesServicioDto>(2, mensaje,
                    new BandejaOrdenesServicioDto(tarjetas, items, total, exportar ? 1 : f.Pagina, exportar ? total : f.PorPagina,
                                                  clientes, responsables));
            },
            ct);

    // ══════════════════════ Lectores comunes ══════════════════════

    private static List<long> Ids(string? csv) =>
        string.IsNullOrWhiteSpace(csv) ? [] :
        csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
           .Select(x => long.TryParse(x, out var n) ? n : 0).Where(n => n > 0).Distinct().ToList();

    private static List<string> Lista(string? texto, string separador) =>
        string.IsNullOrWhiteSpace(texto) ? [] :
        texto.Split(separador, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();

    private static bool Tiene(MySqlDataReader r, string col)
    {
        for (int i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static string? TextoSi(MySqlDataReader r, string col) => Tiene(r, col) ? Texto(r, col) : null;

    /// <summary>Equipo de la ficha, del tab Equipos, del buscador o de la importación (las columnas opcionales se leen si vienen).</summary>
    private static EquipoOrdenServicioDto LeerEquipo(MySqlDataReader r)
    {
        string? otraOs = TextoSi(r, "otra_os");
        string? otraNumero = null, otraEstado = null;
        if (!string.IsNullOrWhiteSpace(otraOs))
        {
            var partes = otraOs.Split('|', 2);
            otraNumero = partes[0];
            otraEstado = partes.Length > 1 ? partes[1] : null;
        }
        var csv = Tiene(r, "conceptos_ids") ? Texto(r, "conceptos_ids") : Tiene(r, "conceptos") ? Texto(r, "conceptos") : null;
        return new EquipoOrdenServicioDto
        {
            IdOsEquipo         = Tiene(r, "id_os_equipo") ? EnteroLargoNulo(r, "id_os_equipo") : null,
            Orden              = Tiene(r, "orden") ? EnteroNulo(r, "orden") : null,
            IdEquipo           = EnteroLargo(r, "id_equipo"),
            CodigoTw           = Texto(r, "codigo_tw") ?? "",
            NumSerie           = Texto(r, "num_serie") ?? "",
            CodigoCliente      = Texto(r, "codigo_cliente"),
            Clasificacion      = Texto(r, "clasificacion") ?? "",
            ClasificacionLabel = Texto(r, "clasificacion_label") ?? "",
            Marca              = Texto(r, "marca") ?? "",
            Modelo             = Texto(r, "modelo") ?? "",
            Alcance            = Texto(r, "alcance_maximo"),
            Ubicacion          = Texto(r, "ubicacion_especifica"),
            Sede               = Texto(r, "sede"),
            DivisionMinima     = Texto(r, "division_minima"),
            DivisionVerif      = Texto(r, "division_verif"),
            ClaseExactitud     = Texto(r, "clase_exactitud"),
            Escala             = Texto(r, "escala_graduacion"),
            PuntosCalibracion  = Texto(r, "puntos_calibracion"),
            ValorNominal       = Texto(r, "valor_nominal"),
            EstadoEjecucion    = TextoSi(r, "estado_ejecucion"),
            // En el tab Equipos "conceptos" trae las descripciones y "conceptos_ids" los ids; en la ficha "conceptos" son los ids
            Conceptos          = Ids(csv),
            ConceptosDescripcion = Tiene(r, "conceptos_ids") ? Lista(Texto(r, "conceptos"), " | ") : [],
            Sugerido           = Tiene(r, "sugerido") && Booleano(r, "sugerido"),
            OtraOsNumero       = otraNumero,
            OtraOsEstado       = otraEstado,
        };
    }

    private static async Task<List<EquipoOrdenServicioDto>> LeerEquiposAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<EquipoOrdenServicioDto>();
        await r.NextResultAsync(ct);
        while (await r.ReadAsync(ct)) lista.Add(LeerEquipo(r));
        return lista;
    }

    private static ConceptoCatalogoOsDto LeerConceptoCatalogo(MySqlDataReader r) => new(
        EnteroLargo(r, "id_suministro"), Texto(r, "codigo") ?? "", Texto(r, "descripcion") ?? "",
        TextoSi(r, "tipo"), TextoSi(r, "tipo_label"), TextoSi(r, "subtipo"), TextoSi(r, "subtipo_label"),
        Tiene(r, "aplica_servicio") && Booleano(r, "aplica_servicio"), Tiene(r, "aplica_metrologia") && Booleano(r, "aplica_metrologia"));

    private static PropuestaOrigenOsDto LeerPropuesta(MySqlDataReader r, bool ficha) => new()
    {
        IdPropuesta        = EnteroLargo(r, "id_propuesta"),
        Numero             = Texto(r, ficha ? "numero_propuesta" : "numero") ?? "",
        Version            = Entero(r, ficha ? "version_propuesta" : "version"),
        Estado             = Texto(r, ficha ? "estado_propuesta" : "estado"),
        TipoServicio       = Texto(r, "tipo_servicio"),
        FechaAceptacion    = FechaHora(r, "fecha_aceptacion"),
        Comercial          = Texto(r, ficha ? "comercial_emisor" : "comercial"),
        AprobadorVb        = Texto(r, "aprobador_vb"),
        MontoTotal         = DecimalNulo(r, "monto_total"),
        SimboloMoneda      = Texto(r, "simbolo_moneda"),
        EquiposCotizados   = Entero(r, "equipos_cotizados"),
        ConceptosCotizados = Entero(r, "conceptos_cotizados"),
        CondicionPago      = Texto(r, "condicion_pago"),
    };

    private static async Task<List<PersonalAsignadoOsDto>> LeerPersonalAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<PersonalAsignadoOsDto>();
        await r.NextResultAsync(ct);
        while (await r.ReadAsync(ct))
            lista.Add(new PersonalAsignadoOsDto(EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? "", Texto(r, "rol_en_servicio"),
                                                TextoSi(r, "estado_ssoma")));
        return lista;
    }

    private static async Task<List<OpcionImportacionDto>> LeerCodigosAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<OpcionImportacionDto>();
        await r.NextResultAsync(ct);
        while (await r.ReadAsync(ct))
            lista.Add(new OpcionImportacionDto(null, Texto(r, "codigo"), Texto(r, "nombre") ?? ""));
        return lista;
    }

    private static object Json(object? valor) =>
        valor is null ? DBNull.Value : System.Text.Json.JsonSerializer.Serialize(valor);

    // ══════════════════════ HU-40 Crear / editar ══════════════════════

    public Task<RespuestaDto<FichaOrdenServicioDto>> PrepararAsync(long? idPropuesta, long? idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", Valor(idPropuesta));
                p.AddWithValue("p_id_os",        Valor(idOs));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<FichaOrdenServicioDto>(3, "No se encontró la orden.");
                var tipo = Texto(r, "tipo") ?? "OS";
                var ficha = new FichaOrdenServicioDto
                {
                    Modo                   = Texto(r, "modo") ?? "nueva",
                    IdOs                   = EnteroLargoNulo(r, "id_os"),
                    Numero                 = Texto(r, "numero") ?? "",
                    Tipo                   = tipo,
                    Estado                 = Texto(r, "estado") ?? "borrador",
                    IdSolicitudAprobada    = EnteroLargoNulo(r, "id_solicitud_aprobada"),
                    MotivoEdicion          = Texto(r, "motivo_edicion"),
                    EdicionAprobadaPor     = Texto(r, "edicion_aprobada_por"),
                    CargoAprobadorEdicion  = Texto(r, "cargo_aprobador_edicion"),
                    FechaAprobacionEdicion = FechaHora(r, "fecha_aprobacion_edicion"),
                    IdCliente              = EnteroLargo(r, "id_cliente"),
                    RazonSocial            = Texto(r, "razon_social") ?? "",
                    Ruc                    = Texto(r, "ruc"),
                    IdSede                 = EnteroLargoNulo(r, "id_sede"),
                    Sede                   = Texto(r, "sede"),
                    DireccionOperaciones   = Texto(r, "direccion_operaciones"),
                    IdContacto             = EnteroLargoNulo(r, "id_contacto"),
                    IdResponsable          = EnteroLargoNulo(r, "id_responsable"),
                    Responsable            = Texto(r, "responsable"),
                    CargoResponsable       = Texto(r, "cargo_responsable"),
                    Propuesta              = LeerPropuesta(r, ficha: true),
                    FechaEmision           = FechaHora(r, "fecha_emision") ?? DateTime.Now,
                    IdRequerimiento        = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq               = Texto(r, "numero_rq"),
                    FechaProgramadaDesde   = FechaHora(r, "fecha_programada_desde"),
                    FechaProgramadaHasta   = FechaHora(r, "fecha_programada_hasta"),
                    Observaciones          = Texto(r, "observaciones"),
                    Certificado            = tipo == "OM"
                        ? new CertificadoOsDto(Booleano(r, "es_tercerizado"), Booleano(r, "es_tercerizado"), Texto(r, "cert_razon_social"),
                                               Texto(r, "cert_ruc"), Texto(r, "cert_direccion"), Texto(r, "cert_contacto"))
                        : null,
                };

                await r.NextResultAsync(ct);
                var contactos = new List<ContactoClienteOsDto>();
                while (await r.ReadAsync(ct))
                    contactos.Add(new ContactoClienteOsDto(EnteroLargo(r, "id_contacto"), Texto(r, "nombres") ?? "", Texto(r, "cargo"),
                                                           Texto(r, "correo"), Texto(r, "telefono"), Booleano(r, "es_principal")));

                await r.NextResultAsync(ct);
                var conceptos = new List<ConceptoOrdenServicioDto>();
                while (await r.ReadAsync(ct))
                    conceptos.Add(new ConceptoOrdenServicioDto
                    {
                        IdSuministro  = EnteroLargoNulo(r, "id_suministro"),
                        Codigo        = Texto(r, "codigo"),
                        Descripcion   = Texto(r, "descripcion") ?? "",
                        Sugerido      = Booleano(r, "sugerido"),
                        Clasificacion = Texto(r, "clasificacion"),
                    });

                var equipos = await LeerEquiposAsync(r, ct);
                // Relación concepto ↔ equipos (la columna "Aplica a" de la sección Conceptos)
                conceptos = conceptos.Select(c => c with
                {
                    EquiposAplicados = equipos.Where(e => c.IdSuministro is long id && e.Conceptos.Contains(id)).Select(e => e.CodigoTw).ToList(),
                }).ToList();

                return new RespuestaDto<FichaOrdenServicioDto>(2, mensaje, ficha with { Contactos = contactos, Conceptos = conceptos, Equipos = equipos });
            },
            ct);

    public Task<RespuestaDto<OrdenServicioGuardadaDto>> GuardarAsync(long idOs, GuardarOrdenServicioDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_propuesta", Valor(d.IdPropuesta));
                p.AddWithValue("p_datos", Json(new Dictionary<string, object?>
                {
                    ["idContacto"]           = d.IdContacto,
                    ["fechaProgramadaDesde"] = d.FechaProgramadaDesde?.ToString("yyyy-MM-dd"),
                    ["fechaProgramadaHasta"] = d.FechaProgramadaHasta?.ToString("yyyy-MM-dd"),
                    ["observaciones"]        = d.Observaciones,
                    ["certRazonSocial"]      = d.CertRazonSocial,
                    ["certRuc"]              = d.CertRuc,
                    ["certDireccion"]        = d.CertDireccion,
                    ["certContacto"]         = d.CertContacto,
                }));
                p.AddWithValue("p_conceptos", Json(d.Conceptos.Select(c => new { idSuministro = c })));
                p.AddWithValue("p_equipos",   Json(d.Equipos.Select(e => new { idEquipo = e.IdEquipo, conceptos = e.Conceptos })));
                p.AddWithValue("p_emitir",    Bit(d.Emitir));
                p.AddWithValue("p_importacion", d.Importacion is { } i
                    ? Json(new { nombreArchivo = i.NombreArchivo, modo = i.Modo, conceptos = i.Conceptos, equipos = i.Equipos,
                                 relaciones = i.Relaciones, advertencias = i.Advertencias })
                    : DBNull.Value);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<OrdenServicioGuardadaDto>(2, mensaje, new OrdenServicioGuardadaDto(
                        EnteroLargo(r, "id_os"), Texto(r, "numero") ?? "", Texto(r, "tipo") ?? "OS", Texto(r, "estado") ?? ""))
                    : new RespuestaDto<OrdenServicioGuardadaDto>(2, mensaje);
            },
            ct);

    public Task<RespuestaDto<PreparacionSolicitudEdicionOsDto>> PrepararSolicitudEdicionAsync(long idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararSolicitudEdicionOrdenServicio",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<PreparacionSolicitudEdicionOsDto>(3, "No se encontró la orden.");
                var (id, numero, tipo, estado, razon) = (EnteroLargo(r, "id_os"), Texto(r, "numero") ?? "", Texto(r, "tipo") ?? "OS",
                                                         Texto(r, "estado") ?? "", Texto(r, "razon_social"));
                var (idAprobador, aprobador, cargo, sede, disponible) = (EnteroLargoNulo(r, "id_aprobador"), Texto(r, "aprobador"),
                    Texto(r, "cargo_aprobador"), Texto(r, "sede_aprobador"), Booleano(r, "aprobador_disponible"));
                var motivos = await LeerOpcionesAsync(r, ct);
                return new RespuestaDto<PreparacionSolicitudEdicionOsDto>(2, mensaje, new PreparacionSolicitudEdicionOsDto(
                    id, numero, tipo, estado, razon, idAprobador, aprobador, cargo, sede, disponible, motivos));
            },
            ct);

    public Task<RespuestaDto<SolicitudEdicionOsDto>> SolicitarEdicionAsync(long idOs, int idMotivo, string comentario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_SolicitarEdicionOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_id_motivo",  idMotivo);
                p.AddWithValue("p_comentario", comentario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<SolicitudEdicionOsDto>(2, mensaje, LeerSolicitud(r, "solicitante", null))
                    : new RespuestaDto<SolicitudEdicionOsDto>(2, mensaje);
            },
            ct);

    public Task<RespuestaDto<SolicitudEdicionOsDto>> ResolverSolicitudEdicionAsync(long idSolicitud, bool aprobar, string? comentario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverSolicitudEdicionOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_solicitud", idSolicitud);
                p.AddWithValue("p_aprobar",      Bit(aprobar));
                p.AddWithValue("p_comentario",   Valor(comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<SolicitudEdicionOsDto>(2, mensaje, LeerSolicitud(r, "resuelto_por", Booleano(r, "aprobada")))
                    : new RespuestaDto<SolicitudEdicionOsDto>(2, mensaje);
            },
            ct);

    private static SolicitudEdicionOsDto LeerSolicitud(MySqlDataReader r, string columnaAutor, bool? aprobada) => new()
    {
        IdSolicitud        = EnteroLargo(r, "id_solicitud"),
        IdOs               = EnteroLargo(r, "id_os"),
        Numero             = Texto(r, "numero") ?? "",
        Tipo               = Texto(r, "tipo") ?? "OS",
        RazonSocial        = Texto(r, "razon_social"),
        Motivo             = Texto(r, "motivo"),
        Comentario         = Texto(r, "comentario"),
        Autor              = Texto(r, columnaAutor),
        Aprobada           = aprobada,
        IdDestinatario     = EnteroLargoNulo(r, "id_destinatario"),
        Destinatario       = Texto(r, "destinatario"),
        CorreoDestinatario = Texto(r, "correo_destinatario"),
    };

    public Task<RespuestaDto<PreparacionAnulacionOsDto>> PrepararAnulacionAsync(long idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararAnulacionOrdenServicio",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<PreparacionAnulacionOsDto>(3, "No se encontró la orden.");
                var dto = new PreparacionAnulacionOsDto(
                    EnteroLargo(r, "id_os"), Texto(r, "numero") ?? "", Texto(r, "tipo") ?? "OS", Texto(r, "estado") ?? "", Texto(r, "razon_social"),
                    Booleano(r, "tiene_programacion"), Texto(r, "tecnico"), FechaHora(r, "fecha_ejecucion"),
                    Texto(r, "hora_inicio"), Texto(r, "hora_fin_estimada"), DecimalNulo(r, "viaticos"), Texto(r, "simbolo_moneda"), [], []);
                var personal = await LeerPersonalAsync(r, ct);
                var motivos = await LeerOpcionesAsync(r, ct);
                return new RespuestaDto<PreparacionAnulacionOsDto>(2, mensaje, dto with { Personal = personal, Motivos = motivos });
            },
            ct);

    public Task<RespuestaDto<AnulacionOrdenServicioDto>> AnularAsync(long idOs, int idMotivo, string comentario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AnularOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_id_motivo",  idMotivo);
                p.AddWithValue("p_comentario", comentario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<AnulacionOrdenServicioDto>(2, mensaje, new AnulacionOrdenServicioDto(
                        EnteroLargo(r, "id_os"), Texto(r, "numero") ?? "", Texto(r, "estado") ?? "anulada",
                        Ent(r, "personal_liberado"), Ent(r, "viaticos_liberados")))
                    : new RespuestaDto<AnulacionOrdenServicioDto>(2, mensaje);
            },
            ct);

    // ══════════════════════ HU-42 Detalle ══════════════════════

    public Task<RespuestaDto<DetalleOrdenServicioDto>> ObtenerDetalleAsync(long idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleOrdenServicio",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DetalleOrdenServicioDto>(3, "No se encontró la orden.");
                var idSolicitud = EnteroLargoNulo(r, "id_solicitud_pendiente");
                var d = new DetalleOrdenServicioDto
                {
                    IdOs                   = EnteroLargo(r, "id_os"),
                    Tipo                   = Texto(r, "tipo") ?? "OS",
                    Numero                 = Texto(r, "numero") ?? "",
                    Estado                 = Texto(r, "estado") ?? "",
                    EstadoGrupo            = Texto(r, "estado_grupo") ?? "",
                    EstadoLabel            = Texto(r, "estado_label") ?? "",
                    IdCliente              = EnteroLargoNulo(r, "id_cliente"),
                    RazonSocial            = Texto(r, "razon_social"),
                    Ruc                    = Texto(r, "ruc"),
                    DireccionOperaciones   = Texto(r, "direccion_operaciones"),
                    IdContacto             = EnteroLargoNulo(r, "id_contacto"),
                    Contacto               = Texto(r, "contacto"),
                    CargoContacto          = Texto(r, "cargo_contacto"),
                    TelefonoContacto       = Texto(r, "telefono_contacto"),
                    CorreoContacto         = Texto(r, "correo_contacto"),
                    IdResponsable          = EnteroLargoNulo(r, "id_responsable"),
                    Responsable            = Texto(r, "responsable"),
                    FechaEmision           = FechaHora(r, "fecha_emision"),
                    FechaDocumento         = FechaHora(r, "fecha_documento"),
                    FechaProgramadaDesde   = FechaHora(r, "fecha_programada_desde"),
                    FechaProgramadaHasta   = FechaHora(r, "fecha_programada_hasta"),
                    IdPropuesta            = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta        = Texto(r, "numero_propuesta"),
                    VersionPropuesta       = EnteroNulo(r, "version_propuesta"),
                    IdRequerimiento        = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq               = Texto(r, "numero_rq"),
                    IdExpediente           = EnteroLargoNulo(r, "id_expediente"),
                    NumeroEquipos          = Ent(r, "n_equipos"),
                    NumeroConceptos        = Ent(r, "n_conceptos"),
                    SolicitudPendiente     = idSolicitud is long ids
                        ? new SolicitudPendienteOsDto(ids, Texto(r, "motivo_solicitud"), Texto(r, "comentario_solicitud"), FechaHora(r, "fecha_solicitud"),
                                                      EnteroLargoNulo(r, "id_solicitante"), Texto(r, "solicitante"),
                                                      EnteroLargoNulo(r, "id_aprobador"), Texto(r, "aprobador_solicitud"))
                        : null,
                    EdicionAprobada        = Booleano(r, "edicion_aprobada"),
                    PuedeEditar            = Booleano(r, "puede_editar"),
                    PuedeSolicitarEdicion  = Booleano(r, "puede_solicitar_edicion"),
                    PuedeResolverSolicitud = Booleano(r, "puede_resolver_solicitud"),
                    PuedeAnular            = Booleano(r, "puede_anular"),
                    MotivoAnulacion        = Texto(r, "motivo_anulacion"),
                    ComentarioAnulacion    = Texto(r, "comentario_anulacion"),
                    AnuladoEn              = FechaHora(r, "anulado_en"),
                    AnuladoPor             = Texto(r, "anulado_por"),
                    UltimaActualizacion    = FechaHora(r, "ultima_actualizacion"),
                    ActualizadoPor         = Texto(r, "actualizado_por"),
                };

                await r.NextResultAsync(ct);
                var equipos = new List<AvanceEquipoOsDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(new AvanceEquipoOsDto(
                        EnteroLargo(r, "id_os_equipo"), EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw") ?? "", Texto(r, "clasificacion") ?? "",
                        Texto(r, "clasificacion_label") ?? "", Texto(r, "marca") ?? "", Texto(r, "modelo") ?? "", Texto(r, "num_serie") ?? "",
                        Texto(r, "estado_ejecucion") ?? "pendiente", FechaHora(r, "fecha_ejecucion"), Texto(r, "observacion_ejecucion")));

                return new RespuestaDto<DetalleOrdenServicioDto>(2, mensaje, d with { Avance = new AvanceOrdenServicioDto(0, 0, 0, 0, 0, 0, equipos) });
            },
            ct);

    private Task<RespuestaDto<T>> TabAsync<T>(long idOs, string tab, long idUsuario,
                                              Func<MySqlDataReader, string, Task<RespuestaDto<T>>> leer, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerTabOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_tab",        tab);
            },
            leer, ct);

    public Task<RespuestaDto<PropuestaOrigenOsDto>> ObtenerPropuestaOrigenAsync(long idOs, long idUsuario, CancellationToken ct)
        => TabAsync(idOs, "propuesta", idUsuario, async (r, mensaje) =>
        {
            await r.NextResultAsync(ct);
            return await r.ReadAsync(ct)
                ? new RespuestaDto<PropuestaOrigenOsDto>(2, mensaje, LeerPropuesta(r, ficha: false))
                : new RespuestaDto<PropuestaOrigenOsDto>(1, "La orden no tiene propuesta de origen.");
        }, ct);

    public Task<RespuestaDto<List<EquipoOrdenServicioDto>>> ObtenerEquiposAsync(long idOs, long idUsuario, CancellationToken ct)
        => TabAsync(idOs, "equipos", idUsuario, async (r, mensaje) =>
            new RespuestaDto<List<EquipoOrdenServicioDto>>(2, mensaje, await LeerEquiposAsync(r, ct)), ct);

    public Task<RespuestaDto<List<ConceptoOrdenServicioDto>>> ObtenerConceptosAsync(long idOs, long idUsuario, CancellationToken ct)
        => TabAsync(idOs, "conceptos", idUsuario, async (r, mensaje) =>
        {
            await r.NextResultAsync(ct);
            var lista = new List<ConceptoOrdenServicioDto>();
            while (await r.ReadAsync(ct))
                lista.Add(new ConceptoOrdenServicioDto
                {
                    IdOsConcepto     = EnteroLargoNulo(r, "id_os_concepto"),
                    IdSuministro     = EnteroLargoNulo(r, "id_suministro"),
                    Codigo           = Texto(r, "codigo"),
                    Descripcion      = Texto(r, "descripcion") ?? "",
                    EquiposAplicados = Lista(Texto(r, "equipos_aplicados"), ","),
                });
            return new RespuestaDto<List<ConceptoOrdenServicioDto>>(2, mensaje, lista);
        }, ct);

    public Task<RespuestaDto<string?>> ObtenerObservacionesAsync(long idOs, long idUsuario, CancellationToken ct)
        => TabAsync(idOs, "observaciones", idUsuario, async (r, mensaje) =>
        {
            await r.NextResultAsync(ct);
            return new RespuestaDto<string?>(2, mensaje, await r.ReadAsync(ct) ? Texto(r, "observaciones") : null);
        }, ct);

    public Task<RespuestaDto<ProgramacionOrdenServicioDto>> ObtenerProgramacionAsync(long idOs, long idUsuario, CancellationToken ct)
        => TabAsync(idOs, "programacion", idUsuario, async (r, mensaje) =>
        {
            await r.NextResultAsync(ct);
            if (!await r.ReadAsync(ct)) return new RespuestaDto<ProgramacionOrdenServicioDto>(3, "No se encontró la orden.");
            var tiene = Booleano(r, "tiene_programacion");
            var dto = new ProgramacionOrdenServicioDto(
                Texto(r, "estado") ?? "", tiene, EnteroLargoNulo(r, "id_tecnico_principal"), Texto(r, "tecnico"), FechaHora(r, "fecha_ejecucion"),
                Texto(r, "hora_inicio"), Texto(r, "hora_fin_estimada"), Texto(r, "hora_llegada_real"), Texto(r, "hora_fin_real"),
                Texto(r, "estado_preparacion"), Booleano(r, "confirmacion_cliente"), DecimalNulo(r, "viaticos"), Texto(r, "simbolo_moneda"),
                Texto(r, "notas_operativas"), [],
                tiene ? null : "Esta orden aún no ha sido programada. Operaciones asignará fecha y técnico.");
            var personal = await LeerPersonalAsync(r, ct);
            return new RespuestaDto<ProgramacionOrdenServicioDto>(2, mensaje, dto with { Personal = personal });
        }, ct);

    public Task<RespuestaDto<CertificadoOsDto>> ObtenerCertificadoAsync(long idOs, long idUsuario, CancellationToken ct)
        => TabAsync(idOs, "certificado", idUsuario, async (r, mensaje) =>
        {
            await r.NextResultAsync(ct);
            if (!await r.ReadAsync(ct)) return new RespuestaDto<CertificadoOsDto>(3, "No se encontró la orden.");
            var tercerizado = Booleano(r, "es_tercerizado");
            return new RespuestaDto<CertificadoOsDto>(2, mensaje, new CertificadoOsDto(
                tercerizado, false, Texto(r, "cert_razon_social"), Texto(r, "cert_ruc"), Texto(r, "cert_direccion"), Texto(r, "cert_contacto")));
        }, ct);

    // ══════════════════════ HU-43 Buscadores ══════════════════════

    public Task<RespuestaDto<BusquedaEquiposOsDto>> BuscarEquiposAsync(FiltrosBuscarEquiposOsDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_BuscarEquiposClienteOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_cliente",    f.IdCliente);
                p.AddWithValue("p_id_os",         Valor(f.IdOs));
                p.AddWithValue("p_busqueda",      Valor(f.Busqueda));
                p.AddWithValue("p_clasificacion", Valor(f.Clasificacion));
                p.AddWithValue("p_ubicacion",     Valor(f.Ubicacion));
                p.AddWithValue("p_pagina",        f.Pagina);
                p.AddWithValue("p_por_pagina",    f.PorPagina);
            },
            async (r, mensaje) =>
            {
                var items = await LeerEquiposAsync(r, ct);
                var total = await LeerTotalAsync(r, ct);
                await r.NextResultAsync(ct);
                var ubicaciones = new List<string>();
                while (await r.ReadAsync(ct)) if (Texto(r, "nombre") is { } u) ubicaciones.Add(u);
                var clasificaciones = await LeerCodigosAsync(r, ct);
                return new RespuestaDto<BusquedaEquiposOsDto>(2, mensaje, new BusquedaEquiposOsDto(items, total, ubicaciones, clasificaciones));
            },
            ct);

    public Task<RespuestaDto<BusquedaConceptosOsDto>> BuscarConceptosAsync(FiltrosBuscarConceptosOsDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_BuscarConceptosServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_busqueda",   Valor(f.Busqueda));
                p.AddWithValue("p_tipo",       Valor(f.Tipo));
                p.AddWithValue("p_pagina",     f.Pagina);
                p.AddWithValue("p_por_pagina", f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<ConceptoCatalogoOsDto>();
                while (await r.ReadAsync(ct)) items.Add(LeerConceptoCatalogo(r));
                var total = await LeerTotalAsync(r, ct);
                var tipos = await LeerCodigosAsync(r, ct);
                return new RespuestaDto<BusquedaConceptosOsDto>(2, mensaje, new BusquedaConceptosOsDto(items, total, tipos));
            },
            ct);

    // ══════════════════════ HU-44 Importación ══════════════════════

    public Task<RespuestaDto<CandidatosImportacionOsDto>> ObtenerCandidatosImportacionAsync(
        long idCliente, long? idOs, IReadOnlyList<string> codigosTw, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCandidatosImportacionOrdenServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_cliente", idCliente);
                p.AddWithValue("p_id_os",      Valor(idOs));
                p.AddWithValue("p_codigos_tw", Json(codigosTw));
            },
            async (r, mensaje) =>
            {
                var equipos = await LeerEquiposAsync(r, ct);
                await r.NextResultAsync(ct);
                var noDisponibles = new List<(string, string)>();
                while (await r.ReadAsync(ct)) noDisponibles.Add((Texto(r, "codigo_tw") ?? "", Texto(r, "motivo") ?? ""));
                await r.NextResultAsync(ct);
                var conceptos = new List<ConceptoCatalogoOsDto>();
                while (await r.ReadAsync(ct)) conceptos.Add(LeerConceptoCatalogo(r));
                return new RespuestaDto<CandidatosImportacionOsDto>(2, mensaje, new CandidatosImportacionOsDto(equipos, noDisponibles, conceptos));
            },
            ct);

    private static async Task<List<OpcionFiltroDto>> LeerOpcionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<OpcionFiltroDto>();
        await r.NextResultAsync(ct);
        while (await r.ReadAsync(ct))
            lista.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return lista;
    }
}
