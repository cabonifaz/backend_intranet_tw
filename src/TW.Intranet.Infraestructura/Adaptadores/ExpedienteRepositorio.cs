using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Expediente Digital (Sprint 4, HU-29 a HU-33).</summary>
public class ExpedienteRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IExpedienteRepositorio
{
    // Los SP devuelven enteros como BIGINT o DECIMAL según la expresión: se leen siempre por conversión.
    private static int Ent(MySqlDataReader r, string c) => EsNulo(r, c) ? 0 : Convert.ToInt32(r[c]);
    private static int? EntNulo(MySqlDataReader r, string c) => EsNulo(r, c) ? null : Convert.ToInt32(r[c]);
    private static bool Bool(MySqlDataReader r, string c) => !EsNulo(r, c) && Convert.ToInt64(r[c]) != 0;
    private static bool? BoolNulo(MySqlDataReader r, string c) => EsNulo(r, c) ? null : Convert.ToInt64(r[c]) != 0;

    /// <summary>DATETIME o DATE (DateTime o DateOnly según el conector).</summary>
    private static DateTime? Fh(MySqlDataReader r, string c) => EsNulo(r, c) ? null : r[c] switch
    {
        DateTime d => d,
        DateOnly d => d.ToDateTime(TimeOnly.MinValue),
        var otro   => Convert.ToDateTime(otro),
    };

    /// <summary>TIME → "HH:mm".</summary>
    private static string? Hora(MySqlDataReader r, string c) => EsNulo(r, c) ? null : r[c] switch
    {
        TimeSpan t => t.ToString(@"hh\:mm"),
        TimeOnly t => t.ToString("HH:mm"),
        var otro   => Convert.ToString(otro),
    };

    private static async Task<List<T>> LeerListaAsync<T>(MySqlDataReader r, Func<MySqlDataReader, T> leer, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var lista = new List<T>();
        while (await r.ReadAsync(ct)) lista.Add(leer(r));
        return lista;
    }

    private static async Task<T?> LeerUnoAsync<T>(MySqlDataReader r, Func<MySqlDataReader, T> leer, CancellationToken ct) where T : class
    {
        await r.NextResultAsync(ct);
        return await r.ReadAsync(ct) ? leer(r) : null;
    }

    private static SlaExpedienteDto Sla(MySqlDataReader r) => new(
        Fh(r, "inicio_etapa"), EntNulo(r, "sla_horas"), Fh(r, "fecha_limite"), Texto(r, "sla_estado"), EntNulo(r, "sla_minutos_restantes"));

    private static OpcionExpedienteDto Opcion(MySqlDataReader r) => new(Texto(r, "codigo") ?? "", Texto(r, "nombre") ?? "");
    private static OpcionIdExpedienteDto OpcionId(MySqlDataReader r) => new(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo"));

    private static EventoExpedienteDto Evento(MySqlDataReader r) => new(
        Fh(r, "fecha") ?? DateTime.MinValue, Texto(r, "tipo_evento"), TieneColumna(r, "accion") ? Texto(r, "accion") : null,
        Texto(r, "titulo"), Texto(r, "descripcion"), Texto(r, "etapa"), Texto(r, "etapa_nombre"),
        EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario") ?? "Sistema", Texto(r, "entidad"), Texto(r, "referencia"),
        Bool(r, "urgente"), Texto(r, "origen"))
    {
        CargoUsuario = TieneColumna(r, "cargo_usuario") ? Texto(r, "cargo_usuario") : null,
    };

    private static EventoTabDto EventoTab(MySqlDataReader r) => new(
        Fh(r, "fecha"), Texto(r, "tipo"), Texto(r, "titulo"), Texto(r, "descripcion"), EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario"));

    private static bool TieneColumna(MySqlDataReader r, string c)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), c, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    /// <summary>"clave|nombre;clave|nombre" → archivos (adjuntos de una interacción de seguimiento).</summary>
    private static IReadOnlyList<ArchivoTabDto> Adjuntos(string? texto) =>
        string.IsNullOrWhiteSpace(texto)
            ? []
            : texto.Split(';', StringSplitOptions.RemoveEmptyEntries)
                   .Select(x => x.Split('|', 2))
                   .Select(p => new ArchivoTabDto(p[0], p.Length > 1 ? p[1] : null, null, null, null, null))
                   .ToList();

    private static EntidadExpedienteDto Entidad(MySqlDataReader x) => new()
    {
        Clave             = Texto(x, "clave") ?? "",
        ClavePadre        = Texto(x, "clave_padre"),
        Nivel             = Ent(x, "nivel"),
        EntidadTipo       = Texto(x, "entidad_tipo") ?? "",
        IdEntidad         = EnteroLargo(x, "id_entidad"),
        Codigo            = Texto(x, "codigo"),
        Version           = EntNulo(x, "version"),
        Estado            = Texto(x, "estado"),
        Monto             = DecimalNulo(x, "monto"),
        SimboloMoneda     = Texto(x, "simbolo_moneda"),
        IdResponsable     = EnteroLargoNulo(x, "id_responsable"),
        Responsable       = Texto(x, "responsable"),
        Fecha             = TieneColumna(x, "fecha") ? Fh(x, "fecha") : null,
        FechaEnvio        = TieneColumna(x, "fecha_envio") ? Fh(x, "fecha_envio") : null,
        FechaCierre       = TieneColumna(x, "fecha_cierre") ? Fh(x, "fecha_cierre") : null,
        Detalle           = Texto(x, "detalle"),
        Activa            = !TieneColumna(x, "activa") || Bool(x, "activa"),
        EsPropuestaActiva = Bool(x, "es_activa_exp"),
    };

    private static void Base(MySqlParameterCollection p, long idUsuario, long idExpediente)
    {
        p.AddWithValue("p_id_usuario",    idUsuario);
        p.AddWithValue("p_id_expediente", idExpediente);
    }

    // ── HU-29 Bandeja ────────────────────────────────────────────────────────

    public Task<RespuestaDto<BandejaExpedientesDto>> ObtenerBandejaAsync(FiltrosBandejaExpedientesDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaExpedientes",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_etapa",          Valor(f.Etapa));
                p.AddWithValue("p_id_cliente",     Valor(f.IdCliente));
                p.AddWithValue("p_area",           Valor(f.Area));
                p.AddWithValue("p_tipo_propuesta", Valor(f.TipoPropuesta));
                p.AddWithValue("p_desde",          Valor(f.Desde?.Date));
                p.AddWithValue("p_hasta",          Valor(f.Hasta?.Date));
                p.AddWithValue("p_sla",            Valor(f.Sla));
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
                p.AddWithValue("p_exportar",       Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = await r.ReadAsync(ct)
                    ? new TarjetasExpedientesDto(Ent(r, "activos"), Ent(r, "listos_para_avanzar"), Ent(r, "bloqueados"),
                                                 Ent(r, "con_excepcion"), Ent(r, "sla_vencidos"))
                    : new TarjetasExpedientesDto(0, 0, 0, 0, 0);

                var filas = await LeerListaAsync(r, x => new FilaExpedienteDto
                {
                    IdExpediente       = EnteroLargo(x, "id_expediente"),
                    Numero             = Texto(x, "numero") ?? "",
                    IdRequerimiento    = EnteroLargoNulo(x, "id_requerimiento"),
                    NumeroRq           = Texto(x, "numero_rq"),
                    IdPropuesta        = EnteroLargoNulo(x, "id_propuesta"),
                    NumeroPropuesta    = Texto(x, "numero_propuesta"),
                    VersionPropuesta   = EntNulo(x, "version_propuesta"),
                    EstadoPropuesta    = Texto(x, "estado_propuesta"),
                    PropuestasOtras    = Ent(x, "propuestas_otras"),
                    IdCliente          = EnteroLargoNulo(x, "id_cliente"),
                    RazonSocial        = Texto(x, "razon_social"),
                    Ruc                = Texto(x, "ruc"),
                    CantidadOc         = Ent(x, "cantidad_oc"),
                    NumerosOc          = Texto(x, "numeros_oc"),
                    NumeroOsOm         = Texto(x, "numero_os_om"),
                    NumerosOs          = Texto(x, "numeros_os"),
                    NumerosOm          = Texto(x, "numeros_om"),
                    TipoPropuesta      = Texto(x, "tipo_servicio"),
                    Etapa              = Texto(x, "etapa") ?? "",
                    EtapaNombre        = Texto(x, "etapa_nombre"),
                    Estado             = Texto(x, "estado") ?? "",
                    ListoParaAvanzar   = Bool(x, "listo"),
                    Progreso           = Ent(x, "progreso"),
                    Area               = Texto(x, "area"),
                    AreaNombre         = Texto(x, "area_nombre"),
                    IdResponsable      = EnteroLargoNulo(x, "id_responsable"),
                    Responsable        = Texto(x, "responsable"),
                    IdResponsableEtapa = EnteroLargoNulo(x, "id_responsable_etapa"),
                    ResponsableEtapa   = Texto(x, "responsable_etapa"),
                    Bloqueos           = Ent(x, "bloqueos"),
                    Excepciones        = Ent(x, "excepciones"),
                    MotivoBloqueo      = Texto(x, "motivo_bloqueo"),
                    Sla                = Sla(x),
                    FechaCreacion      = Fh(x, "fecha_creacion"),
                    DiasTranscurridos  = Ent(x, "dias_transcurridos"),
                }, ct);

                var total    = await LeerTotalAsync(r, ct);
                var estados  = await LeerListaAsync(r, Opcion, ct);
                var etapas   = await LeerListaAsync(r, Opcion, ct);
                var clientes = await LeerListaAsync(r, x => new ClienteFiltroExpedienteDto(
                    EnteroLargo(x, "id_cliente"), Texto(x, "razon_social") ?? "", Texto(x, "ruc")), ct);
                var areas    = await LeerListaAsync(r, Opcion, ct);
                var tipos    = await LeerListaAsync(r, Opcion, ct);
                var slas     = await LeerListaAsync(r, Opcion, ct);

                return new RespuestaDto<BandejaExpedientesDto>(2, mensaje,
                    new BandejaExpedientesDto(tarjetas, filas, total, f.Pagina, f.PorPagina, estados, etapas, clientes, areas, tipos, slas));
            },
            ct);

    // ── HU-30 Ficha: cabecera, KPIs y Resumen ────────────────────────────────

    public Task<RespuestaDto<DetalleExpedienteDto>> ObtenerDetalleAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DetalleExpedienteDto>(3, "No se pudo leer el expediente.");
                var c = new CabeceraExpedienteDto
                {
                    IdExpediente         = EnteroLargo(r, "id_expediente"),
                    Numero               = Texto(r, "numero") ?? "",
                    Estado               = Texto(r, "estado") ?? "",
                    Etapa                = Texto(r, "etapa") ?? "",
                    EtapaNombre          = Texto(r, "etapa_nombre"),
                    EtapaComercial       = Bool(r, "etapa_comercial"),
                    Progreso             = Ent(r, "progreso"),
                    IdCliente            = EnteroLargoNulo(r, "id_cliente"),
                    RazonSocial          = Texto(r, "razon_social"),
                    Ruc                  = Texto(r, "ruc"),
                    AreaServicio         = Texto(r, "area_servicio"),
                    Area                 = Texto(r, "area"),
                    AreaNombre           = Texto(r, "area_nombre"),
                    IdResponsable        = EnteroLargoNulo(r, "id_responsable"),
                    Responsable          = Texto(r, "responsable"),
                    CargoResponsable     = Texto(r, "cargo_responsable"),
                    IdResponsableEtapa   = EnteroLargoNulo(r, "id_responsable_etapa"),
                    ResponsableEtapa     = Texto(r, "responsable_etapa"),
                    IdRequerimiento      = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq             = Texto(r, "numero_rq"),
                    IdPropuesta          = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta      = Texto(r, "numero_propuesta"),
                    VersionPropuesta     = EntNulo(r, "version_propuesta"),
                    EstadoPropuesta      = Texto(r, "estado_propuesta"),
                    TipoPropuesta        = Texto(r, "tipo_servicio"),
                    MontoTotal           = DecimalNulo(r, "monto_total"),
                    Moneda               = Texto(r, "moneda"),
                    SimboloMoneda        = Texto(r, "simbolo_moneda"),
                    FechaCreacion        = Fh(r, "fecha_creacion"),
                    FechaCierre          = Fh(r, "fecha_cierre"),
                    DiasTranscurridos    = Ent(r, "dias_transcurridos"),
                    Sla                  = Sla(r),
                    DocumentosTotales    = Ent(r, "documentos_totales"),
                    BloqueosActivos      = Ent(r, "bloqueos_activos"),
                    ExcepcionesActivas   = Ent(r, "excepciones_activas"),
                    MotivoBloqueo        = Texto(r, "motivo_bloqueo"),
                    ListoParaAvanzar     = Bool(r, "listo_para_avanzar"),
                    SiguienteEtapa       = Texto(r, "siguiente_etapa"),
                    SiguienteEtapaNombre = Texto(r, "siguiente_etapa_nombre"),
                    ProximoPaso          = Texto(r, "proximo_paso"),
                    CantidadPropuestas   = Ent(r, "cantidad_propuestas"),
                    CantidadOc           = Ent(r, "cantidad_oc"),
                    CantidadVb           = Ent(r, "cantidad_vb"),
                    CantidadOs           = Ent(r, "cantidad_os"),
                    PuedeReasignar       = Bool(r, "puede_reasignar"),
                    PuedeExportar        = Bool(r, "puede_exportar"),
                };

                var etapas = await LeerListaAsync(r, x => new EtapaExpedienteDto(
                    Ent(x, "orden"), Texto(x, "etapa") ?? "", Texto(x, "nombre") ?? "", Texto(x, "estado") ?? "",
                    Texto(x, "area"), Texto(x, "area_nombre"), Fh(x, "inicio"), Fh(x, "fin"), EnteroLargoNulo(x, "id_responsable"),
                    Texto(x, "responsable"), EntNulo(x, "sla_horas"), DecimalNulo(x, "horas_reales"), BoolNulo(x, "cumple_sla")), ct);
                var responsables = await LeerListaAsync(r, x => new ResponsableActualDto(
                    Texto(x, "rol") ?? "", EnteroLargoNulo(x, "id_usuario"), Texto(x, "nombre"), Texto(x, "cargo")), ct);
                var entidades = await LeerListaAsync(r, Entidad, ct);
                var alertas = await LeerListaAsync(r, x => new AlertaExpedienteDto(
                    Texto(x, "clave") ?? "", Texto(x, "clase") ?? "", Texto(x, "tipo"), Texto(x, "tipo_nombre"), Texto(x, "etapa"),
                    Texto(x, "etapa_nombre"), Texto(x, "entidad_tipo"), EnteroLargoNulo(x, "id_entidad"), Texto(x, "entidad"),
                    Texto(x, "motivo"), Texto(x, "impacto"), Bool(x, "critico"), Fh(x, "fecha"), Texto(x, "origen"),
                    EnteroLargoNulo(x, "id_usuario"), Texto(x, "usuario")), ct);
                var actividad = await LeerListaAsync(r, Evento, ct);

                return new RespuestaDto<DetalleExpedienteDto>(2, mensaje,
                    new DetalleExpedienteDto(c, etapas, responsables, entidades, alertas, actividad));
            },
            ct);

    // ── HU-30 Tabs ───────────────────────────────────────────────────────────

    public Task<RespuestaDto<TabRqExpedienteDto>> ObtenerTabRqAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerRqExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var datos = await LeerUnoAsync(r, x => new DatosRqExpedienteDto
                {
                    IdRequerimiento  = EnteroLargo(x, "id_requerimiento"),
                    Numero           = Texto(x, "numero") ?? "",
                    Estado           = Texto(x, "estado"),
                    EstadoNombre     = Texto(x, "estado_nombre"),
                    Origen           = Texto(x, "origen"),
                    GradoNecesidad   = Texto(x, "grado_necesidad"),
                    AreaServicio     = Texto(x, "area_servicio"),
                    Descripcion      = Texto(x, "descripcion"),
                    FechaRequerida   = Fh(x, "fecha_requerida"),
                    FechaRegistro    = Fh(x, "fecha_registro"),
                    FechaCierre      = Fh(x, "fecha_cierre"),
                    RequiereVisita   = Bool(x, "requiere_visita"),
                    EsInacal         = Bool(x, "es_inacal"),
                    IdResponsable    = EnteroLargoNulo(x, "id_responsable"),
                    Responsable      = Texto(x, "responsable"),
                    CargoResponsable = Texto(x, "cargo_responsable"),
                    IdCliente        = EnteroLargoNulo(x, "id_cliente"),
                    RazonSocial      = Texto(x, "razon_social"),
                    Ruc              = Texto(x, "ruc"),
                    ContactoNombre   = Texto(x, "contacto_nombre"),
                    ContactoCargo    = Texto(x, "contacto_cargo"),
                    ContactoArea     = Texto(x, "contacto_area"),
                    ContactoCorreo   = Texto(x, "contacto_correo"),
                    ContactoTelefono = Texto(x, "contacto_telefono"),
                    SedeNombre       = Texto(x, "sede_nombre"),
                    SedeUbicacion    = Texto(x, "sede_ubicacion"),
                    SedeDireccion    = Texto(x, "sede_direccion"),
                }, ct);
                if (datos is null) return new RespuestaDto<TabRqExpedienteDto>(3, "No se pudo leer el requerimiento.");

                var adjuntos = await LeerListaAsync(r, x => new ArchivoTabDto(
                    Texto(x, "clave") ?? "", Texto(x, "nombre_archivo"), Texto(x, "tipo"), EnteroLargoNulo(x, "tamano_bytes"),
                    Fh(x, "fecha_carga"), Texto(x, "usuario")), ct);
                var timeline = await LeerListaAsync(r, EventoTab, ct);
                var propuestas = await LeerListaAsync(r, x => new PropuestaGeneradaDto(
                    EnteroLargo(x, "id_propuesta"), Texto(x, "numero") ?? "", Ent(x, "version"), Texto(x, "estado") ?? "",
                    DecimalNulo(x, "total"), Texto(x, "simbolo_moneda"), EnteroLargoNulo(x, "id_responsable"), Texto(x, "responsable"),
                    Fh(x, "fecha_creacion"), Fh(x, "fecha_envio"), Fh(x, "fecha_aceptacion"), Fh(x, "fecha_rechazo"),
                    Texto(x, "motivo_rechazo")), ct);

                return new RespuestaDto<TabRqExpedienteDto>(2, mensaje, new TabRqExpedienteDto(datos, adjuntos, timeline, propuestas));
            },
            ct);

    public Task<RespuestaDto<TabPropuestasExpedienteDto>> ObtenerTabPropuestasAsync(long idExpediente, long? idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPropuestasExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_id_propuesta", Valor(idPropuesta));
            },
            async (r, mensaje) =>
            {
                var versiones = await LeerListaAsync(r, x => new VersionPropuestaExpedienteDto(
                    EnteroLargo(x, "id_propuesta"), Texto(x, "numero") ?? "", Ent(x, "version"), Texto(x, "estado") ?? "",
                    DecimalNulo(x, "total"), Texto(x, "simbolo_moneda"), Fh(x, "fecha_creacion"), Bool(x, "es_ultima"),
                    Bool(x, "es_activa"), Bool(x, "seleccionada")), ct);
                var detalle = await LeerUnoAsync(r, x => new DetallePropuestaExpedienteDto
                {
                    IdPropuesta        = EnteroLargo(x, "id_propuesta"),
                    Numero             = Texto(x, "numero") ?? "",
                    Version            = Ent(x, "version"),
                    Estado             = Texto(x, "estado") ?? "",
                    TipoPropuesta      = Texto(x, "tipo_servicio"),
                    Referencia         = Texto(x, "referencia"),
                    IdResponsable      = EnteroLargoNulo(x, "id_responsable"),
                    Responsable        = Texto(x, "responsable"),
                    Moneda             = Texto(x, "moneda"),
                    SimboloMoneda      = Texto(x, "simbolo_moneda"),
                    Subtotal           = DecimalNulo(x, "subtotal"),
                    DescuentoMonto     = DecimalNulo(x, "descuento_monto"),
                    DescuentoPct       = DecimalNulo(x, "descuento_pct"),
                    AplicaIgv          = Bool(x, "aplica_igv"),
                    IgvPct             = DecimalNulo(x, "igv_pct"),
                    IgvMonto           = DecimalNulo(x, "igv_monto"),
                    Total              = DecimalNulo(x, "total"),
                    CondicionPago      = Texto(x, "condicion_pago"),
                    PlazoEntregaDias   = EntNulo(x, "plazo_entrega_dias"),
                    VigenciaDias       = EntNulo(x, "vigencia_dias"),
                    FechaExpiracion    = Fh(x, "fecha_expiracion"),
                    FechaCreacion      = Fh(x, "fecha_creacion"),
                    FechaEnvio         = Fh(x, "fecha_envio"),
                    FechaAceptacion    = Fh(x, "fecha_aceptacion"),
                    DescripcionCambios = Texto(x, "descripcion_cambios"),
                    MotivoNuevaVersion = Texto(x, "motivo_nueva_version"),
                    SeccionesActivas   = Texto(x, "secciones_activas"),
                    ClavePdf           = Texto(x, "clave_pdf") ?? "",
                    NombrePdf          = Texto(x, "nombre_pdf"),
                    NumeroRq           = Texto(x, "numero_rq"),
                    IdContacto         = EnteroLargoNulo(x, "id_contacto"),
                    Contacto           = Texto(x, "contacto"),
                    CargoContacto      = Texto(x, "cargo_contacto"),
                    CorreoContacto     = Texto(x, "correo_contacto"),
                    TelefonoContacto   = Texto(x, "telefono_contacto"),
                    IdSede             = EnteroLargoNulo(x, "id_sede"),
                    Sede               = Texto(x, "sede"),
                    Suministros        = Ent(x, "suministros"),
                }, ct);
                var formas = await LeerListaAsync(r, x => new FormaPagoExpedienteDto(
                    DecimalNulo(x, "porcentaje"), Texto(x, "condicion"), Ent(x, "orden")), ct);
                var items = await LeerListaAsync(r, x => new ItemPropuestaExpedienteDto(
                    EnteroLargo(x, "id_item"), Texto(x, "seccion") ?? "", Texto(x, "descripcion"), DecimalNulo(x, "cantidad"),
                    DecimalNulo(x, "precio_unitario"), DecimalNulo(x, "descuento"), DecimalNulo(x, "subtotal"), Texto(x, "alcance"),
                    Texto(x, "puntos_calibracion"), DecimalNulo(x, "frecuencia")), ct);
                var equipos = await LeerListaAsync(r, x => new EquipoPropuestaExpedienteDto(
                    EnteroLargoNulo(x, "id_equipo"), Texto(x, "tipo"), Texto(x, "subtipo"), Texto(x, "marca"), Texto(x, "modelo"),
                    Texto(x, "num_serie"), Texto(x, "codigo_cliente"), Texto(x, "codigo_tw"), Texto(x, "local_sede")), ct);
                var vbs = await LeerListaAsync(r, x => new VistoBuenoVersionDto(
                    EnteroLargo(x, "id_vb"), Texto(x, "estado") ?? "", EnteroLargoNulo(x, "id_aprobador"), Texto(x, "aprobador"),
                    Texto(x, "cargo_aprobador"), Fh(x, "fecha_solicitud"), Fh(x, "fecha_respuesta"), EnteroLargoNulo(x, "id_resuelto_por"),
                    Texto(x, "resuelto_por"), Texto(x, "comentario_respuesta"), Texto(x, "motivo_rechazo")), ct);
                var timeline = await LeerListaAsync(r, EventoTab, ct);
                var ocs = await LeerListaAsync(r, x => new OcPropuestaExpedienteDto(
                    EnteroLargo(x, "id_oc"), Texto(x, "numero_oc") ?? "", Texto(x, "estado") ?? "", Bool(x, "es_autogenerada"),
                    Bool(x, "reemplazada"), EntNulo(x, "id_moneda_oc"), Texto(x, "simbolo_moneda_oc"), DecimalNulo(x, "monto_total") ?? 0,
                    DecimalNulo(x, "monto_asignado") ?? 0, DecimalNulo(x, "monto_cubierto"), Texto(x, "estado_validacion"),
                    Texto(x, "resultado_ia"), EntNulo(x, "criticas"), EntNulo(x, "advertencias"), EnteroLargoNulo(x, "id_responsable"),
                    Texto(x, "responsable"), Fh(x, "fecha_emision"), Fh(x, "fecha_recepcion"), Fh(x, "fecha_registro")), ct);

                return new RespuestaDto<TabPropuestasExpedienteDto>(2, mensaje,
                    new TabPropuestasExpedienteDto(versiones, detalle, formas, items, equipos, vbs, timeline) { OrdenesCompra = ocs });
            },
            ct);

    public Task<RespuestaDto<object>> ValidarComparacionAsync(long idExpediente, long idBase, long idDestino, long idUsuario, CancellationToken ct)
        => EjecutarAsync<object>("SP_ValidarComparacionExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_id_base",    idBase);
                p.AddWithValue("p_id_destino", idDestino);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)),
            ct);

    public Task<RespuestaDto<TabVistoBuenoExpedienteDto>> ObtenerTabVistoBuenoAsync(long idExpediente, string? numero, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerVistoBuenoExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_numero", Valor(numero));
            },
            async (r, mensaje) =>
            {
                var propuestas = await LeerListaAsync(r, PropuestaPill, ct);
                var estado = await LeerUnoAsync(r, x => new EstadoVistoBuenoDto
                {
                    Numero              = Texto(x, "numero"),
                    IdPropuestaRevision = EnteroLargoNulo(x, "id_propuesta_revision"),
                    VersionRevision     = EntNulo(x, "version_revision"),
                    EstadoPropuesta     = Texto(x, "estado_propuesta"),
                    EstadoVb            = Texto(x, "estado_vb"),
                    IdVb                = EnteroLargoNulo(x, "id_vb"),
                    IdAprobador         = EnteroLargoNulo(x, "id_aprobador"),
                    Aprobador           = Texto(x, "aprobador"),
                    CargoAprobador      = Texto(x, "cargo_aprobador"),
                    AreaAprobador       = Texto(x, "area_aprobador"),
                    CorreoAprobador     = Texto(x, "correo_aprobador"),
                    TelefonoAprobador   = Texto(x, "telefono_aprobador"),
                    EstadoAprobador     = Texto(x, "estado_aprobador"),
                    AprobadorPorDefecto = BoolNulo(x, "aprobador_por_defecto"),
                    IdComercial         = EnteroLargoNulo(x, "id_comercial"),
                    Comercial           = Texto(x, "comercial"),
                    EsJefeDirectoComercial = BoolNulo(x, "es_jefe_directo_comercial"),
                    IdPropuestaAprobada = EnteroLargoNulo(x, "id_propuesta_aprobada"),
                    VersionAprobada     = EntNulo(x, "version_aprobada"),
                    MontoAprobado       = DecimalNulo(x, "monto_aprobado"),
                    SimboloMoneda       = Texto(x, "simbolo_moneda"),
                    FechaAprobacion     = Fh(x, "fecha_aprobacion"),
                    FechaSolicitud      = Fh(x, "fecha_solicitud"),
                    SlaHoras            = EntNulo(x, "sla_horas"),
                    HorasHabiles        = DecimalNulo(x, "horas_habiles"),
                    DentroSla           = BoolNulo(x, "dentro_sla"),
                    Comentario          = Texto(x, "comentario"),
                }, ct);
                var decisiones = await LeerListaAsync(r, x => new DecisionVbExpedienteDto(
                    EnteroLargo(x, "id_vb"), EnteroLargo(x, "id_propuesta"), Ent(x, "version"), Texto(x, "estado") ?? "",
                    EnteroLargoNulo(x, "id_aprobador"), Texto(x, "aprobador"), Texto(x, "cargo_aprobador"), EnteroLargoNulo(x, "id_revisor"),
                    Texto(x, "revisor"), Texto(x, "cargo_revisor"), Fh(x, "fecha_solicitud"), Fh(x, "fecha_respuesta"),
                    Texto(x, "comentario"), Texto(x, "motivo_rechazo"), DecimalNulo(x, "horas_revision"), EntNulo(x, "sla_horas")), ct);
                var reasignaciones = await LeerListaAsync(r, x => new ReasignacionAprobadorDto(
                    EnteroLargo(x, "id_vb"), Ent(x, "version"), Fh(x, "fecha"), EnteroLargoNulo(x, "id_anterior"),
                    Texto(x, "aprobador_anterior"), EnteroLargoNulo(x, "id_nuevo"), Texto(x, "aprobador_nuevo"), Texto(x, "motivo"),
                    Texto(x, "comentario"), Texto(x, "ejecutado_por")), ct);
                var metricas = await LeerUnoAsync(r, x => new MetricasVistoBuenoDto(
                    Ent(x, "versiones_totales"), Ent(x, "versiones_devueltas"), DecimalNulo(x, "dias_totales"),
                    DecimalNulo(x, "dias_promedio_revision"), Ent(x, "decisiones_en_sla"), Ent(x, "decisiones")), ct);

                return new RespuestaDto<TabVistoBuenoExpedienteDto>(2, mensaje,
                    new TabVistoBuenoExpedienteDto(propuestas, estado, decisiones, reasignaciones, metricas));
            },
            ct);

    private static PropuestaPillDto PropuestaPill(MySqlDataReader x) =>
        new(Texto(x, "numero") ?? "", Ent(x, "version"), Bool(x, "seleccionada"));

    public Task<RespuestaDto<TabSeguimientoExpedienteDto>> ObtenerTabSeguimientoAsync(long idExpediente, string? numero, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSeguimientoExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_numero", Valor(numero));
            },
            async (r, mensaje) =>
            {
                var propuestas = await LeerListaAsync(r, PropuestaPill, ct);
                var estado = await LeerUnoAsync(r, x => new EstadoSeguimientoExpedienteDto
                {
                    Numero             = Texto(x, "numero"),
                    IdPropuesta        = EnteroLargoNulo(x, "id_propuesta"),
                    Version            = EntNulo(x, "version"),
                    EstadoPropuesta    = Texto(x, "estado_propuesta"),
                    EstadoSeguimiento  = Texto(x, "estado_seguimiento"),
                    FechaEnvio         = Fh(x, "fecha_envio"),
                    FechaCierre        = Fh(x, "fecha_cierre"),
                    DiasSeguimiento    = DecimalNulo(x, "dias_seguimiento"),
                    IdComercial        = EnteroLargoNulo(x, "id_comercial"),
                    Comercial          = Texto(x, "comercial"),
                    CargoComercial     = Texto(x, "cargo_comercial"),
                    CorreoComercial    = Texto(x, "correo_comercial"),
                    TelefonoComercial  = Texto(x, "telefono_comercial"),
                    AreaComercial      = Texto(x, "area_comercial"),
                    Contacto           = Texto(x, "contacto"),
                    CargoContacto      = Texto(x, "cargo_contacto"),
                    CorreoContacto     = Texto(x, "correo_contacto"),
                    UltimaInteraccion  = Fh(x, "ultima_interaccion"),
                    TotalInteracciones = Ent(x, "total_interacciones"),
                    SlaHoras           = EntNulo(x, "sla_horas"),
                    SlaCumplido        = BoolNulo(x, "sla_cumplido"),
                }, ct);
                var interacciones = await LeerListaAsync(r, x => new InteraccionSeguimientoDto(
                    Fh(x, "fecha"), Texto(x, "tipo") ?? "", Texto(x, "titulo"), Texto(x, "canal"), Texto(x, "resultado"),
                    Texto(x, "asunto"), Texto(x, "detalle"), EntNulo(x, "duracion_minutos"), Fh(x, "proxima_accion_fecha"),
                    Texto(x, "proxima_accion"), EntNulo(x, "version"), EnteroLargoNulo(x, "id_usuario"), Texto(x, "usuario"),
                    Adjuntos(Texto(x, "adjuntos")))
                {
                    Destinatario   = Texto(x, "destinatario"),
                    ResumenCuerpo  = Texto(x, "resumen_cuerpo"),
                    TipoAceptacion = Texto(x, "tipo_aceptacion"),
                }, ct);
                var resultado = await LeerUnoAsync(r, x => new ResultadoSeguimientoDto(
                    Texto(x, "resultado") ?? "", Fh(x, "fecha_cierre"), EnteroLargoNulo(x, "id_registrado_por"), Texto(x, "registrado_por"),
                    Texto(x, "tipo_evidencia"), Texto(x, "motivo_rechazo"), Texto(x, "canal"), Texto(x, "comentario"),
                    DecimalNulo(x, "monto_comprometido"), Texto(x, "simbolo_moneda"), DecimalNulo(x, "dias_hasta_cierre"),
                    Bool(x, "permite_reactivacion")), ct);
                var evidencias = await LeerListaAsync(r, x => new ArchivoTabDto(
                    Texto(x, "clave") ?? "", Texto(x, "nombre_archivo"), Texto(x, "tipo_contenido"), EnteroLargoNulo(x, "tamano_bytes"),
                    Fh(x, "fecha"), null), ct);

                return new RespuestaDto<TabSeguimientoExpedienteDto>(2, mensaje,
                    new TabSeguimientoExpedienteDto(propuestas, estado, interacciones, resultado, evidencias));
            },
            ct);

    public Task<RespuestaDto<TabOrdenesCompraExpedienteDto>> ObtenerTabOrdenesCompraAsync(long idExpediente, long? idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerOrdenesCompraExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_id_oc", Valor(idOc));
            },
            async (r, mensaje) =>
            {
                var pills = await LeerListaAsync(r, x => new OcPillDto(
                    EnteroLargo(x, "id_oc"), Texto(x, "numero_oc") ?? "", Texto(x, "estado") ?? "", Bool(x, "es_autogenerada"),
                    Bool(x, "vigente"), EnteroLargoNulo(x, "id_propuesta"), Texto(x, "propuesta"), Bool(x, "seleccionada")), ct);
                var datos = await LeerUnoAsync(r, x => new DatosOcExpedienteDto
                {
                    IdOc                   = EnteroLargo(x, "id_oc"),
                    NumeroOc               = Texto(x, "numero_oc") ?? "",
                    Estado                 = Texto(x, "estado") ?? "",
                    EsAutogenerada         = Bool(x, "es_autogenerada"),
                    Referencia             = Texto(x, "referencia"),
                    FechaEmision           = Fh(x, "fecha_emision"),
                    FechaRecepcion         = Fh(x, "fecha_recepcion"),
                    FechaRegistro          = Fh(x, "fecha_registro"),
                    VigenciaHasta          = Fh(x, "vigencia_hasta"),
                    Moneda                 = Texto(x, "moneda"),
                    SimboloMoneda          = Texto(x, "simbolo_moneda"),
                    MontoTotal             = DecimalNulo(x, "monto_total"),
                    MontoAsignado          = DecimalNulo(x, "monto_asignado"),
                    Saldo                  = DecimalNulo(x, "saldo"),
                    FormaPago              = Texto(x, "forma_pago"),
                    IgvIncluido            = Bool(x, "igv_incluido"),
                    IgvPct                 = DecimalNulo(x, "igv_pct"),
                    FacturaIgualOc         = Bool(x, "factura_igual_oc"),
                    Observaciones          = Texto(x, "observaciones"),
                    ClavePdf               = Texto(x, "clave_pdf"),
                    NombreArchivoPdf       = Texto(x, "nombre_archivo_pdf"),
                    TamanoPdfBytes         = EnteroLargoNulo(x, "tamano_pdf_bytes"),
                    ReemplazadaPor         = Texto(x, "reemplazada_por"),
                    FechaReemplazo         = Fh(x, "fecha_reemplazo"),
                    FechaAnulacion         = Fh(x, "fecha_anulacion"),
                    MotivoAnulacion        = Texto(x, "motivo_anulacion"),
                    JustificacionAnulacion = Texto(x, "justificacion_anulacion"),
                    IdResponsable          = EnteroLargoNulo(x, "id_responsable"),
                    Responsable            = Texto(x, "responsable"),
                    IdRegistradoPor        = EnteroLargoNulo(x, "id_registrado_por"),
                    RegistradoPor          = Texto(x, "registrado_por"),
                }, ct);
                var validaciones = await LeerListaAsync(r, x => new ValidacionOcExpedienteDto(
                    EnteroLargo(x, "id_propuesta"), Texto(x, "propuesta") ?? "", Texto(x, "estado_propuesta"), Bool(x, "de_este_expediente"),
                    DecimalNulo(x, "monto_asignado"), DecimalNulo(x, "porcentaje_oc"), Texto(x, "estado_validacion"),
                    Texto(x, "tipo_observacion"), Texto(x, "resultado_ia"), Fh(x, "fecha_decision"), EntNulo(x, "corrida"),
                    EntNulo(x, "coincidencias"), EntNulo(x, "advertencias"), EntNulo(x, "criticas"), EntNulo(x, "total_campos"),
                    DecimalNulo(x, "confianza"), Texto(x, "motor"), Texto(x, "dictamen"), Texto(x, "sugerencia"),
                    Fh(x, "fecha_validacion")), ct);
                var campos = await LeerListaAsync(r, x => new CampoValidacionOcDto(
                    EntNulo(x, "orden"), Texto(x, "campo"), Texto(x, "etiqueta"), Texto(x, "valor_oc"), Texto(x, "valor_propuesta"),
                    Texto(x, "severidad"), Texto(x, "mensaje")), ct);
                var timeline = await LeerListaAsync(r, x => new EventoOcExpedienteDto(
                    Fh(x, "fecha"), Texto(x, "accion"), Texto(x, "titulo"), Texto(x, "descripcion"), Texto(x, "estado_anterior"),
                    Texto(x, "estado_nuevo"), EnteroLargoNulo(x, "id_usuario"), Texto(x, "usuario"), Bool(x, "automatico_ia")), ct);

                var oss = await LeerListaAsync(r, x => new OsVinculadaOcExpedienteDto(
                    EnteroLargo(x, "id_os"), Texto(x, "numero") ?? "", Texto(x, "estado") ?? "", DecimalNulo(x, "costo_total_estimado"),
                    Fh(x, "fecha_ejecucion"), Hora(x, "hora_inicio"), EnteroLargoNulo(x, "id_tecnico_principal"), Texto(x, "tecnico"),
                    EnteroLargoNulo(x, "id_responsable_comercial"), Texto(x, "responsable_comercial"), Texto(x, "confirmacion_cliente"),
                    EnteroLargo(x, "id_expediente"), Texto(x, "numero_expediente")), ct);

                return new RespuestaDto<TabOrdenesCompraExpedienteDto>(2, mensaje,
                    new TabOrdenesCompraExpedienteDto(pills, datos, validaciones, campos, timeline) { OrdenesServicio = oss });
            },
            ct);

    public Task<RespuestaDto<TabOrdenServicioExpedienteDto>> ObtenerTabOrdenServicioAsync(long idExpediente, long? idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerOrdenServicioExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_id_os", Valor(idOs));
            },
            async (r, mensaje) =>
            {
                var pills = await LeerListaAsync(r, x => new OsPillDto(
                    EnteroLargo(x, "id_os"), Texto(x, "numero") ?? "", Texto(x, "estado") ?? "", Fh(x, "fecha_ejecucion"),
                    Bool(x, "seleccionada")), ct);
                var datos = await LeerUnoAsync(r, x => new DatosOsExpedienteDto
                {
                    IdOs                   = EnteroLargo(x, "id_os"),
                    Numero                 = Texto(x, "numero") ?? "",
                    Estado                 = Texto(x, "estado") ?? "",
                    FechaCreacion          = Fh(x, "fecha_creacion"),
                    FechaEjecucion         = Fh(x, "fecha_ejecucion"),
                    HoraInicio             = Hora(x, "hora_inicio"),
                    HoraFinEstimada        = Hora(x, "hora_fin_estimada"),
                    HoraLlegadaReal        = Hora(x, "hora_llegada_real"),
                    HoraFinReal            = Hora(x, "hora_fin_real"),
                    CostoTotalEstimado     = DecimalNulo(x, "costo_total_estimado"),
                    TipoServicio           = Texto(x, "tipo_servicio"),
                    Sede                   = Texto(x, "sede"),
                    SedeDireccion          = Texto(x, "sede_direccion"),
                    IdTecnicoPrincipal     = EnteroLargoNulo(x, "id_tecnico_principal"),
                    TecnicoPrincipal       = Texto(x, "tecnico_principal"),
                    IdResponsableComercial = EnteroLargoNulo(x, "id_responsable_comercial"),
                    ResponsableComercial   = Texto(x, "responsable_comercial"),
                    ConfirmacionCliente    = Bool(x, "confirmacion_cliente"),
                    FechaConfirmacion      = Fh(x, "fecha_confirmacion_cliente"),
                    CanalConfirmacion      = Texto(x, "canal_confirmacion"),
                    ContactoConfirma       = Texto(x, "contacto_confirma"),
                    NotasOperativas        = Texto(x, "notas_operativas"),
                    GeneradoPor            = Texto(x, "generado_por"),
                }, ct);
                var personal = await LeerListaAsync(r, x => new PersonalOsDto(
                    EnteroLargo(x, "id_usuario"), Texto(x, "nombre"), Texto(x, "cargo"), Texto(x, "rol_en_servicio"),
                    Texto(x, "estado_ssoma")), ct);
                var equipos = await LeerListaAsync(r, x => new EquipoOsDto(
                    EnteroLargo(x, "id_equipo"), Texto(x, "codigo_tw"), Texto(x, "codigo_cliente"), Texto(x, "marca"), Texto(x, "modelo"),
                    Texto(x, "numero_serie"), Texto(x, "ubicacion"), Texto(x, "tipo_intervencion"), Bool(x, "ingresado_en_campo")), ct);
                var gastos = await LeerListaAsync(r, x => new GastoOsDto(
                    EnteroLargo(x, "id_gasto"), Texto(x, "tipo"), Texto(x, "concepto"), DecimalNulo(x, "monto"), Texto(x, "simbolo_moneda"),
                    Texto(x, "descripcion"), Texto(x, "estado"), Fh(x, "fecha_solicitud"), Texto(x, "usuario")), ct);
                var oms = await LeerListaAsync(r, x => new OrdenMetrologiaExpedienteDto(
                    EnteroLargo(x, "id_om"), Texto(x, "numero") ?? "", Texto(x, "estado"), Fh(x, "fecha_calibracion"),
                    Texto(x, "numero_certificado"), Fh(x, "fecha_emision_certificado"), Texto(x, "metrologo")), ct);

                return new RespuestaDto<TabOrdenServicioExpedienteDto>(2, mensaje,
                    new TabOrdenServicioExpedienteDto(pills, datos, personal, equipos, gastos, oms));
            },
            ct);

    public Task<RespuestaDto<TabProgramacionExpedienteDto>> ObtenerTabProgramacionAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerProgramacionExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var calendario = await LeerListaAsync(r, x => new CalendarioOsDto(
                    EnteroLargo(x, "id_os"), Texto(x, "numero") ?? "", Texto(x, "estado") ?? "", Fh(x, "fecha_ejecucion"),
                    Hora(x, "hora_inicio"), Hora(x, "hora_fin_estimada"), EnteroLargoNulo(x, "id_tecnico_principal"),
                    Texto(x, "tecnico_principal"), Texto(x, "sede"), Bool(x, "confirmacion_cliente"), Fh(x, "fecha_confirmacion_cliente")), ct);
                var recursos = await LeerListaAsync(r, x => new RecursoReservadoDto(
                    Texto(x, "os"), Texto(x, "tipo_recurso") ?? "", Texto(x, "recurso"), Texto(x, "detalle"), Texto(x, "estado")), ct);
                var backlog = await LeerListaAsync(r, x => new BacklogProgramacionDto(
                    EnteroLargo(x, "id_backlog"), Texto(x, "os"), Texto(x, "om"), Texto(x, "prioridad"), Texto(x, "tecnico_sugerido"),
                    Fh(x, "fecha_limite"), Texto(x, "estado"), Texto(x, "notas_programacion"), Fh(x, "creado_en"), Fh(x, "modificado_en")), ct);
                var presalida = await LeerListaAsync(r, x => new PresalidaDto(
                    Texto(x, "os"), Texto(x, "descripcion"), Bool(x, "confirmado"), Fh(x, "confirmado_en"), Texto(x, "confirmado_por")), ct);

                return new RespuestaDto<TabProgramacionExpedienteDto>(2, mensaje,
                    new TabProgramacionExpedienteDto(calendario, recursos, backlog, presalida));
            },
            ct);

    public Task<RespuestaDto<TabSsomaExpedienteDto>> ObtenerTabSsomaAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSsomaExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var resumen = await LeerUnoAsync(r, x => new ResumenSsomaDto(
                    Ent(x, "personal"), Ent(x, "habilitados"), Ent(x, "pendientes"), Ent(x, "bloqueados"), Ent(x, "observados"),
                    Ent(x, "vencidos"), Texto(x, "estado_global") ?? ""), ct);
                var checklist = await LeerListaAsync(r, x => new ChecklistSsomaDto(
                    Texto(x, "os"), EnteroLargo(x, "id_usuario"), Texto(x, "tecnico"), Texto(x, "rol_en_servicio"), Texto(x, "estado_ssoma"),
                    EntNulo(x, "id_requisito"), Texto(x, "requisito"), Texto(x, "estado_documento"), Fh(x, "fecha_vencimiento")), ct);
                var documentos = await LeerListaAsync(r, x => new DocumentoSsomaDto(
                    Texto(x, "clave") ?? "", Texto(x, "os"), Texto(x, "tecnico"), Texto(x, "tipo"), Texto(x, "nombre_archivo"),
                    Texto(x, "estado"), Ent(x, "version"), Fh(x, "fecha_carga"), Fh(x, "fecha_vencimiento"), Texto(x, "motivo_observacion"),
                    Texto(x, "aprobado_por")), ct);
                var requisitos = await LeerListaAsync(r, x => new RequisitoSsomaExpedienteDto(
                    Ent(x, "id_requisito"), Texto(x, "requisito"), Bool(x, "es_obligatorio"), Bool(x, "bloquea_servicio"), Texto(x, "sede")), ct);

                return new RespuestaDto<TabSsomaExpedienteDto>(2, mensaje, new TabSsomaExpedienteDto(resumen, checklist, documentos, requisitos));
            },
            ct);

    public Task<RespuestaDto<TabEjecucionExpedienteDto>> ObtenerTabEjecucionAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerEjecucionExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var oss = await LeerListaAsync(r, x => new ResumenEjecucionOsDto(
                    EnteroLargo(x, "id_os"), Texto(x, "numero") ?? "", Texto(x, "estado") ?? "", Fh(x, "fecha_ejecucion"),
                    Hora(x, "hora_inicio"), Hora(x, "hora_llegada_real"), Hora(x, "hora_fin_real"), DecimalNulo(x, "latitud_llegada"),
                    DecimalNulo(x, "longitud_llegada"), Texto(x, "tecnico_principal")), ct);
                var eventos = await LeerListaAsync(r, x => new EventoCampoDto(
                    EnteroLargo(x, "id_evento"), Texto(x, "os"), Fh(x, "fecha"), Ent(x, "id_tipo_evento"), Texto(x, "tipo_evento"),
                    DecimalNulo(x, "latitud"), DecimalNulo(x, "longitud"), Texto(x, "notas"), Bool(x, "sincronizado"), Texto(x, "usuario")), ct);
                var evidencias = await LeerListaAsync(r, x => new EvidenciaEjecucionDto(
                    Texto(x, "clave") ?? "", Texto(x, "os"), Texto(x, "tipo_evidencia"), Texto(x, "nombre_archivo"), Fh(x, "fecha"),
                    DecimalNulo(x, "latitud"), DecimalNulo(x, "longitud"), Texto(x, "validacion_ia"), Bool(x, "override_aprobado"),
                    Texto(x, "usuario")), ct);
                var incidencias = await LeerListaAsync(r, x => new IncidenciaExpedienteDto(
                    EnteroLargo(x, "id_incidencia"), Texto(x, "os"), Texto(x, "tipo"), Texto(x, "descripcion"), Texto(x, "nivel_alerta"),
                    Texto(x, "estado"), Fh(x, "fecha_registro"), Texto(x, "usuario")), ct);
                var demoras = await LeerListaAsync(r, x => new DemoraExpedienteDto(
                    EnteroLargo(x, "id_demora"), Texto(x, "os"), Texto(x, "motivo"), Texto(x, "descripcion"), EntNulo(x, "duracion_minutos"),
                    Fh(x, "fecha_registro"), Texto(x, "usuario")), ct);

                return new RespuestaDto<TabEjecucionExpedienteDto>(2, mensaje,
                    new TabEjecucionExpedienteDto(oss, eventos, evidencias, incidencias, demoras));
            },
            ct);

    public Task<RespuestaDto<TabCierreExpedienteDto>> ObtenerTabCierreAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCierreExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var resumen = await LeerUnoAsync(r, x => new ResumenCierreDto(
                    Texto(x, "estado_cierre") ?? "", Fh(x, "fecha_cierre"), Ent(x, "informes"), Ent(x, "informes_aprobados"),
                    Ent(x, "conformes"), Ent(x, "observadas")), ct);
                var informes = await LeerListaAsync(r, x => new InformeTecnicoExpedienteDto(
                    EnteroLargo(x, "id_informe"), Texto(x, "numero") ?? "", Texto(x, "os"), Ent(x, "version"), Texto(x, "estado") ?? "",
                    Texto(x, "diagnostico_principal"), Texto(x, "hallazgos"), Fh(x, "fecha_creacion"), Fh(x, "fecha_envio_cliente"),
                    Texto(x, "clave_pdf"), Texto(x, "tecnico"), Texto(x, "revisor")), ct);
                var conformidades = await LeerListaAsync(r, x => new ConformidadExpedienteDto(
                    EnteroLargo(x, "id_conformidad"), Texto(x, "informe"), Texto(x, "os"), Texto(x, "tipo"), Texto(x, "estado"),
                    Texto(x, "observaciones"), Fh(x, "registrado_en"), Texto(x, "contacto"), Texto(x, "cargo_contacto")), ct);
                var certificados = await LeerListaAsync(r, x => new CertificadoExpedienteDto(
                    Texto(x, "clave"), Texto(x, "numero") ?? "", Texto(x, "numero_certificado"), Fh(x, "fecha_emision_certificado"),
                    Texto(x, "estado")), ct);

                return new RespuestaDto<TabCierreExpedienteDto>(2, mensaje,
                    new TabCierreExpedienteDto(resumen, informes, conformidades, certificados));
            },
            ct);

    public Task<RespuestaDto<IReadOnlyList<ArchivoExportacionExpedienteDto>>> ObtenerArchivosExportacionAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerArchivosExportacionExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var lista = await LeerListaAsync(r, x => new ArchivoExportacionExpedienteDto(
                    Texto(x, "clave") ?? "", Texto(x, "categoria") ?? "", Texto(x, "carpeta") ?? "", Texto(x, "nombre_archivo") ?? "",
                    Ent(x, "version"), Texto(x, "estado") ?? "", Texto(x, "ruta"), EnteroLargoNulo(x, "id_propuesta"), Correo(x)), ct);
                return new RespuestaDto<IReadOnlyList<ArchivoExportacionExpedienteDto>>(2, mensaje, lista);
            },
            ct);

    private static CorreoSeguimientoArchivoDto? Correo(MySqlDataReader x) =>
        EnteroLargoNulo(x, "id_correo") is { } id
            ? new CorreoSeguimientoArchivoDto(id, Texto(x, "correo_asunto"), Texto(x, "correo_para"), Texto(x, "correo_cc"),
                                              Texto(x, "correo_cuerpo"), Fh(x, "correo_fecha"), Texto(x, "correo_remitente"))
            : null;

    // ── HU-31 Documentos ─────────────────────────────────────────────────────

    public Task<RespuestaDto<DocumentosExpedienteDto>> ObtenerDocumentosAsync(long idExpediente, FiltrosDocumentosExpedienteDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDocumentosExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_categoria", Valor(f.Categoria));
                p.AddWithValue("p_busqueda",  Valor(f.Busqueda));
                p.AddWithValue("p_desde",     Valor(f.Desde?.Date));
                p.AddWithValue("p_hasta",     Valor(f.Hasta?.Date));
                p.AddWithValue("p_estado",    Valor(f.Estado));
                p.AddWithValue("p_formato",   Valor(f.Formato));
                p.AddWithValue("p_orden",     Valor(f.Orden));
                p.AddWithValue("p_exportar",  Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DocumentosExpedienteDto>(3, "No se pudo leer el expediente.");
                long idExp = EnteroLargo(r, "id_expediente");
                string numero = Texto(r, "numero") ?? "";
                string? razon = Texto(r, "razon_social"), ruc = Texto(r, "ruc");
                int total = Ent(r, "total_documentos");

                var pestanas = await LeerListaAsync(r, x => new PestanaDocumentosDto(
                    Texto(x, "codigo") ?? "", Texto(x, "nombre") ?? "", Ent(x, "cantidad")), ct);
                var documentos = await LeerListaAsync(r, x => new DocumentoExpedienteDto
                {
                    Clave           = Texto(x, "clave") ?? "",
                    Nombre          = Texto(x, "nombre") ?? "",
                    NombreArchivo   = Texto(x, "nombre_archivo"),
                    Tipo            = Texto(x, "tipo"),
                    Categoria       = Texto(x, "categoria") ?? "",
                    Origen          = Texto(x, "origen"),
                    Modulo          = Texto(x, "modulo"),
                    EtapaOrigen     = Texto(x, "etapa_origen"),
                    Etapa           = Texto(x, "etapa"),
                    EtapaNombre     = Texto(x, "etapa_nombre"),
                    Version         = Ent(x, "version"),
                    Estado          = Texto(x, "estado") ?? "",
                    Fecha           = Fh(x, "fecha"),
                    IdUsuario       = EnteroLargoNulo(x, "id_usuario"),
                    Usuario         = Texto(x, "usuario"),
                    CargoUsuario    = Texto(x, "cargo_usuario"),
                    AreaUsuario     = Texto(x, "area_usuario"),
                    TamanoBytes     = EnteroLargoNulo(x, "tamano_bytes"),
                    TipoContenido   = Texto(x, "tipo_contenido"),
                    Formato         = Texto(x, "formato"),
                    Descripcion     = Texto(x, "descripcion"),
                    Visibilidad     = Texto(x, "visibilidad"),
                    EsInterno       = Bool(x, "es_interno"),
                    Descargable     = Bool(x, "descargable"),
                    Previsualizable = Bool(x, "previsualizable"),
                }, ct);
                var estados  = await LeerListaAsync(r, Opcion, ct);
                var formatos = await LeerListaAsync(r, Opcion, ct);

                return new RespuestaDto<DocumentosExpedienteDto>(2, mensaje,
                    new DocumentosExpedienteDto(idExp, numero, razon, ruc, total, pestanas, documentos, estados, formatos));
            },
            ct);

    public Task<RespuestaDto<UbicacionArchivoExpedienteDto>> ObtenerArchivoAsync(long idExpediente, string clave, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerArchivoExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_clave", clave);
            },
            async (r, mensaje) =>
            {
                var u = await LeerUnoAsync(r, x => new UbicacionArchivoExpedienteDto(
                    Texto(x, "ruta"), Texto(x, "nombre_archivo") ?? "documento", Texto(x, "tipo_contenido"),
                    EnteroLargoNulo(x, "id_propuesta"), Correo(x)), ct);
                return u is null
                    ? new RespuestaDto<UbicacionArchivoExpedienteDto>(3, "No se pudo leer el documento.")
                    : new RespuestaDto<UbicacionArchivoExpedienteDto>(2, mensaje, u);
            },
            ct);

    // ── HU-32 Auditoría ──────────────────────────────────────────────────────

    public Task<RespuestaDto<HistorialExpedienteDto>> ObtenerHistorialAsync(long idExpediente, FiltrosHistorialExpedienteDto f, string? tabExportado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerHistorialExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_busqueda",          Valor(f.Busqueda));
                p.AddWithValue("p_id_usuario_evento", Valor(f.IdUsuario));
                p.AddWithValue("p_etapa",             Valor(f.Etapa));
                p.AddWithValue("p_tipo_evento",       Valor(f.TipoEvento));
                p.AddWithValue("p_desde",             Valor(f.Desde?.Date));
                p.AddWithValue("p_hasta",             Valor(f.Hasta?.Date));
                p.AddWithValue("p_exportar",          Valor(tabExportado));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<HistorialExpedienteDto>(3, "No se pudo leer el expediente.");
                long idExp = EnteroLargo(r, "id_expediente");
                string numero = Texto(r, "numero") ?? "";
                string? razon = Texto(r, "razon_social"), ruc = Texto(r, "ruc"), responsable = Texto(r, "responsable");
                long? idResp = EnteroLargoNulo(r, "id_responsable");

                var tabs = await LeerListaAsync(r, x => new TabAuditoriaDto(Texto(x, "codigo") ?? "", Texto(x, "nombre") ?? "", Ent(x, "cantidad")), ct);
                var timeline = await LeerListaAsync(r, Evento, ct);
                var reasignaciones = await LeerListaAsync(r, x => new ReasignacionHistorialDto(
                    EnteroLargoNulo(x, "id_reasignacion"), Fh(x, "fecha"), Texto(x, "modo"), Texto(x, "alcance"), Texto(x, "entidades"),
                    EnteroLargoNulo(x, "id_de"), Texto(x, "de"), EnteroLargoNulo(x, "id_a"), Texto(x, "a"), Texto(x, "motivo"),
                    Texto(x, "comentario"), Texto(x, "gestion_sla"), Texto(x, "decision_sla"), EnteroLargoNulo(x, "id_ejecutado_por"),
                    Texto(x, "ejecutado_por"), Texto(x, "etapa")), ct);
                var bloqueos = await LeerListaAsync(r, x => new BloqueoHistorialDto(
                    Texto(x, "clave") ?? "", Fh(x, "fecha"), Texto(x, "clase") ?? "", Texto(x, "tipo"), Texto(x, "tipo_nombre"),
                    Texto(x, "etapa"), Texto(x, "etapa_nombre"), Texto(x, "entidad_tipo"), Texto(x, "entidad"), Texto(x, "motivo"),
                    Texto(x, "impacto"), Fh(x, "fecha_resolucion"), Texto(x, "resolucion"), Bool(x, "activo"),
                    DecimalNulo(x, "duracion_horas"), EnteroLargoNulo(x, "id_usuario"), Texto(x, "usuario"), Texto(x, "origen")), ct);
                var alertas = await LeerListaAsync(r, x => new AlertaSlaHistorialDto(
                    Fh(x, "fecha"), Texto(x, "etapa") ?? "", Texto(x, "etapa_nombre"), Texto(x, "nivel") ?? "", EntNulo(x, "sla_horas"),
                    DecimalNulo(x, "horas_reales"), DecimalNulo(x, "desvio_horas"), EnteroLargoNulo(x, "id_responsable"),
                    Texto(x, "responsable"), Texto(x, "accion_tomada")), ct);
                var tipos    = await LeerListaAsync(r, Opcion, ct);
                var usuarios = await LeerListaAsync(r, x => new UsuarioFiltroDto(EnteroLargo(x, "id_usuario"), Texto(x, "nombre") ?? ""), ct);
                var etapas   = await LeerListaAsync(r, Opcion, ct);

                return new RespuestaDto<HistorialExpedienteDto>(2, mensaje,
                    new HistorialExpedienteDto(idExp, numero, razon, ruc, idResp, responsable, tabs, timeline, reasignaciones,
                                               bloqueos, alertas, tipos, usuarios, etapas));
            },
            ct);

    // ── HU-33 Reasignación ───────────────────────────────────────────────────

    public Task<RespuestaDto<PreparacionReasignacionExpedienteDto>> PrepararReasignacionAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararReasignacionExpediente",
            p => Base(p, idUsuario, idExpediente),
            async (r, mensaje) =>
            {
                var datos = await LeerUnoAsync(r, x => new DatosReasignacionExpedienteDto(
                    EnteroLargo(x, "id_expediente"), Texto(x, "numero") ?? "", Texto(x, "razon_social"), Texto(x, "ruc"),
                    Texto(x, "etapa") ?? "", Texto(x, "etapa_nombre"), EnteroLargoNulo(x, "id_responsable"), Texto(x, "responsable"),
                    Texto(x, "cargo_responsable"), Texto(x, "area_responsable"),
                    new SlaExpedienteDto(null, EntNulo(x, "sla_horas"), Fh(x, "fecha_limite"), Texto(x, "sla_estado"),
                                         EntNulo(x, "sla_minutos_restantes")),
                    Texto(x, "nota_impacto") ?? ""), ct);
                if (datos is null) return new RespuestaDto<PreparacionReasignacionExpedienteDto>(3, "No se pudo leer el expediente.");

                var entidades = await LeerListaAsync(r, Entidad, ct);
                var motivos   = await LeerListaAsync(r, OpcionId, ct);
                var gestiones = await LeerListaAsync(r, Opcion, ct);

                return new RespuestaDto<PreparacionReasignacionExpedienteDto>(2, mensaje,
                    new PreparacionReasignacionExpedienteDto(datos, entidades, motivos, gestiones));
            },
            ct);

    public Task<RespuestaDto<CarteraComercialExpedienteDto>> ObtenerCarteraComercialAsync(long idExpediente, long? idResponsable, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCarteraComercialExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_id_responsable", Valor(idResponsable));
            },
            async (r, mensaje) =>
            {
                var resumen = await LeerUnoAsync(r, x => new ResumenCarteraComercialDto(
                    EnteroLargo(x, "id_responsable"), Texto(x, "responsable"), Texto(x, "cargo_responsable"), Texto(x, "area_responsable"),
                    Ent(x, "total_entidades"), Ent(x, "expedientes"), Ent(x, "requerimientos"), Ent(x, "propuestas"),
                    Ent(x, "ordenes_compra"), Ent(x, "ordenes_servicio")), ct);
                if (resumen is null) return new RespuestaDto<CarteraComercialExpedienteDto>(3, "No se pudo leer la cartera del comercial.");

                var expedientes = await LeerListaAsync(r, x => (
                    Id: EnteroLargo(x, "id_expediente"), Numero: Texto(x, "numero") ?? "", Cliente: Texto(x, "cliente"),
                    Etapa: Texto(x, "etapa") ?? "", EtapaNombre: Texto(x, "etapa_nombre"), SlaEstado: Texto(x, "sla_estado"),
                    Minutos: EntNulo(x, "sla_minutos_restantes"), Limite: Fh(x, "fecha_limite"), Entidades: Ent(x, "entidades")), ct);
                var entidades = await LeerListaAsync(r, x => new EntidadCarteraDto(
                    EnteroLargo(x, "id_expediente"), Texto(x, "entidad_tipo") ?? "", EnteroLargo(x, "id_entidad"), Texto(x, "codigo"),
                    Texto(x, "estado"), Texto(x, "detalle")), ct);

                var porExpediente = entidades.ToLookup(e => e.IdExpediente);
                var filas = expedientes.Select(e => new ExpedienteCarteraDto(
                    e.Id, e.Numero, e.Cliente, e.Etapa, e.EtapaNombre, e.SlaEstado, e.Minutos, e.Limite, e.Entidades,
                    porExpediente[e.Id].ToList())).ToList();

                return new RespuestaDto<CarteraComercialExpedienteDto>(2, mensaje, new CarteraComercialExpedienteDto(resumen, filas));
            },
            ct);

    public Task<RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>> BuscarResponsablesAsync(string? busqueda, long? idExcluir, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_BuscarResponsablesExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_busqueda",   Valor(busqueda));
                p.AddWithValue("p_id_excluir", Valor(idExcluir));
            },
            async (r, mensaje) =>
            {
                var lista = await LeerListaAsync(r, x => new CandidatoResponsableDto(
                    EnteroLargo(x, "id_usuario"), Texto(x, "nombre") ?? "", Texto(x, "correo"), Texto(x, "cargo"), Texto(x, "area"),
                    Texto(x, "area_nombre"), Texto(x, "rol_sistema"), Texto(x, "sede_operativa")), ct);
                return new RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>(2, mensaje, lista);
            },
            ct);

    public Task<RespuestaDto<ReasignacionExpedienteDto>> ReasignarResponsableAsync(long idExpediente, ReasignarResponsableExpedienteDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ReasignarResponsableExpediente",
            p =>
            {
                Base(p, idUsuario, idExpediente);
                p.AddWithValue("p_modo",                  Valor(d.Modo));
                p.AddWithValue("p_entidad_tipo",          Valor(d.EntidadTipo));
                p.AddWithValue("p_id_entidad",            Valor(d.IdEntidad));
                p.AddWithValue("p_excluidos",             d.Excluidos is { Count: > 0 } ? JsonSerializer.Serialize(d.Excluidos) : DBNull.Value);
                p.AddWithValue("p_id_responsable_actual", Valor(d.IdResponsableActual));
                p.AddWithValue("p_id_nuevo",              Valor(d.IdNuevoResponsable));
                p.AddWithValue("p_id_motivo",             Valor(d.IdMotivo));
                p.AddWithValue("p_comentario",            Valor(d.Comentario));
                p.AddWithValue("p_gestion_sla",           Valor(d.GestionSla));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ReasignacionExpedienteDto>(3, "No se pudo leer la reasignación.");
                var resultado = new ReasignacionExpedienteDto
                {
                    IdReasignacion    = EnteroLargo(r, "id_reasignacion"),
                    Modo              = Texto(r, "modo") ?? "",
                    Alcance           = Texto(r, "alcance"),
                    TotalEntidades    = Ent(r, "total_entidades"),
                    TotalExpedientes  = Ent(r, "total_expedientes"),
                    IdExpediente      = EnteroLargo(r, "id_expediente"),
                    NumeroExpediente  = Texto(r, "numero_expediente"),
                    IdResponsable     = EnteroLargo(r, "id_responsable"),
                    Responsable       = Texto(r, "responsable") ?? "",
                    CorreoResponsable = Texto(r, "correo_responsable"),
                    Motivo            = Texto(r, "motivo"),
                    Comentario        = Texto(r, "comentario"),
                    GestionSla        = Texto(r, "gestion_sla"),
                    ReasignadoPor     = Texto(r, "reasignado_por"),
                };
                var entidades = await LeerListaAsync(r, x => new EntidadReasignadaDto(
                    EnteroLargo(x, "id_expediente"), Texto(x, "numero_expediente") ?? "", Texto(x, "cliente"), Texto(x, "entidad_tipo") ?? "",
                    EnteroLargo(x, "id_entidad"), Texto(x, "codigo"), EnteroLargoNulo(x, "id_anterior"), Texto(x, "responsable_anterior")), ct);
                var anteriores = await LeerListaAsync(r, x => new ResponsableAnteriorDto(
                    EnteroLargo(x, "id_usuario"), Texto(x, "nombre") ?? "", Texto(x, "correo"), Ent(x, "cantidad"), Texto(x, "codigos")), ct);

                return new RespuestaDto<ReasignacionExpedienteDto>(2, mensaje,
                    resultado with { Entidades = entidades, ResponsablesAnteriores = anteriores });
            },
            ct);
}
