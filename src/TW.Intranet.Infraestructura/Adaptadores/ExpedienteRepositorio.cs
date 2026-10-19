using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Expediente Digital (HU-29 a HU-34).</summary>
public class ExpedienteRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IExpedienteRepositorio
{
    // Los SP devuelven enteros como BIGINT o DECIMAL según la expresión: se leen siempre por conversión.
    private static int Ent(MySqlDataReader r, string c) => EsNulo(r, c) ? 0 : Convert.ToInt32(r[c]);
    private static int? EntNulo(MySqlDataReader r, string c) => EsNulo(r, c) ? null : Convert.ToInt32(r[c]);
    private static bool Bool(MySqlDataReader r, string c) => !EsNulo(r, c) && Convert.ToInt64(r[c]) != 0;
    private static bool? BoolNulo(MySqlDataReader r, string c) => EsNulo(r, c) ? null : Convert.ToInt64(r[c]) != 0;

    private static async Task<List<T>> LeerListaAsync<T>(MySqlDataReader r, Func<MySqlDataReader, T> leer, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var lista = new List<T>();
        while (await r.ReadAsync(ct)) lista.Add(leer(r));
        return lista;
    }

    private static SlaExpedienteDto Sla(MySqlDataReader r) => new(
        FechaHora(r, "inicio_etapa"), EntNulo(r, "sla_horas"), FechaHora(r, "fecha_limite"),
        Texto(r, "sla_estado"), EntNulo(r, "sla_minutos_restantes"));

    private static OpcionExpedienteDto Opcion(MySqlDataReader r) => new(Texto(r, "codigo") ?? "", Texto(r, "nombre") ?? "");
    private static OpcionIdExpedienteDto OpcionId(MySqlDataReader r) => new(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo"));

    private static EventoExpedienteDto Evento(MySqlDataReader r) => new(
        FechaHora(r, "fecha") ?? DateTime.MinValue, Texto(r, "tipo_evento"), TieneColumna(r, "accion") ? Texto(r, "accion") : null,
        Texto(r, "titulo"), Texto(r, "descripcion"), Texto(r, "etapa"),
        TieneColumna(r, "etapa_nombre") ? Texto(r, "etapa_nombre") : null,
        EnteroLargoNulo(r, "id_usuario"), Texto(r, "usuario") ?? "Sistema",
        TieneColumna(r, "entidad") ? Texto(r, "entidad") : null, Texto(r, "referencia"), Bool(r, "urgente"));

    private static bool TieneColumna(MySqlDataReader r, string c)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), c, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static ValidacionEtapaDto Validacion(MySqlDataReader r) => new(
        Ent(r, "orden"), Texto(r, "codigo") ?? "", Texto(r, "descripcion") ?? "", Bool(r, "cumple"), Bool(r, "critico"),
        Bool(r, "es_documento"), Texto(r, "detalle"), Texto(r, "accion_sugerida"));

    // ── HU-29 Bandeja ────────────────────────────────────────────────────────

    public Task<RespuestaDto<BandejaExpedientesDto>> ObtenerBandejaAsync(FiltrosBandejaExpedientesDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaExpedientes",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_estado",     Valor(f.Estado));
                p.AddWithValue("p_etapa",      Valor(f.Etapa));
                p.AddWithValue("p_id_cliente", Valor(f.IdCliente));
                p.AddWithValue("p_area",       Valor(f.Area));
                p.AddWithValue("p_busqueda",   Valor(f.Busqueda));
                p.AddWithValue("p_pagina",     f.Pagina);
                p.AddWithValue("p_por_pagina", f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = await r.ReadAsync(ct)
                    ? new TarjetasExpedientesDto(Ent(r, "activos"), Ent(r, "listos_para_avanzar"), Ent(r, "bloqueados"),
                                                 Ent(r, "con_excepcion"), Ent(r, "sla_vencidos"), Ent(r, "pendientes_cierre"))
                    : new TarjetasExpedientesDto(0, 0, 0, 0, 0, 0);

                var filas = await LeerListaAsync(r, x => new FilaExpedienteDto
                {
                    IdExpediente    = EnteroLargo(x, "id_expediente"),
                    Numero          = Texto(x, "numero") ?? "",
                    Estado          = Texto(x, "estado") ?? "",
                    Etapa           = Texto(x, "etapa") ?? "",
                    EtapaNombre     = Texto(x, "etapa_nombre"),
                    Progreso        = Ent(x, "progreso"),
                    IdCliente       = EnteroLargoNulo(x, "id_cliente"),
                    RazonSocial     = Texto(x, "razon_social"),
                    Ruc             = Texto(x, "ruc"),
                    IdRequerimiento = EnteroLargoNulo(x, "id_requerimiento"),
                    NumeroRq        = Texto(x, "numero_rq"),
                    IdPropuesta     = EnteroLargoNulo(x, "id_propuesta"),
                    Propuesta       = Texto(x, "propuesta"),
                    NumerosOc       = Texto(x, "numeros_oc"),
                    NumerosOs       = Texto(x, "numeros_os"),
                    NumerosOm       = Texto(x, "numeros_om"),
                    TipoServicio    = Texto(x, "tipo_servicio"),
                    Area            = Texto(x, "area"),
                    AreaNombre      = Texto(x, "area_nombre"),
                    IdResponsable   = EnteroLargoNulo(x, "id_responsable"),
                    Responsable     = Texto(x, "responsable"),
                    Prioridad       = Texto(x, "prioridad"),
                    Bloqueos        = Ent(x, "bloqueos"),
                    Excepciones     = Ent(x, "excepciones"),
                    MotivoBloqueo   = Texto(x, "motivo_bloqueo"),
                    Sla             = Sla(x),
                    FechaCreacion   = FechaHora(x, "fecha_creacion"),
                }, ct);

                var total    = await LeerTotalAsync(r, ct);
                var estados  = await LeerListaAsync(r, Opcion, ct);
                var etapas   = await LeerListaAsync(r, Opcion, ct);
                var clientes = await LeerListaAsync(r, x => new ClienteFiltroExpedienteDto(
                    EnteroLargo(x, "id_cliente"), Texto(x, "razon_social") ?? "", Texto(x, "ruc")), ct);
                var areas    = await LeerListaAsync(r, Opcion, ct);

                return new RespuestaDto<BandejaExpedientesDto>(2, mensaje,
                    new BandejaExpedientesDto(tarjetas, filas, total, f.Pagina, f.PorPagina, estados, etapas, clientes, areas));
            },
            ct);

    // ── HU-30 Detalle y workflow ─────────────────────────────────────────────

    public Task<RespuestaDto<DetalleExpedienteDto>> ObtenerDetalleAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DetalleExpedienteDto>(3, "No se pudo leer el expediente.");
                var resumen = new ResumenExpedienteDto
                {
                    IdExpediente        = EnteroLargo(r, "id_expediente"),
                    Numero              = Texto(r, "numero") ?? "",
                    Estado              = Texto(r, "estado") ?? "",
                    Etapa               = Texto(r, "etapa") ?? "",
                    EtapaNombre         = Texto(r, "etapa_nombre"),
                    Progreso            = Ent(r, "progreso"),
                    IdCliente           = EnteroLargoNulo(r, "id_cliente"),
                    RazonSocial         = Texto(r, "razon_social"),
                    Ruc                 = Texto(r, "ruc"),
                    IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq            = Texto(r, "numero_rq"),
                    DescripcionRq       = Texto(r, "descripcion_rq"),
                    IdPropuesta         = EnteroLargoNulo(r, "id_propuesta"),
                    Propuesta           = Texto(r, "propuesta"),
                    NumerosOc           = Texto(r, "numeros_oc"),
                    NumerosOs           = Texto(r, "numeros_os"),
                    NumerosOm           = Texto(r, "numeros_om"),
                    TipoServicio        = Texto(r, "tipo_servicio"),
                    Equipos             = Ent(r, "equipos"),
                    Ubicacion           = Texto(r, "ubicacion"),
                    Area                = Texto(r, "area"),
                    AreaNombre          = Texto(r, "area_nombre"),
                    IdResponsable       = EnteroLargoNulo(r, "id_responsable"),
                    Responsable         = Texto(r, "responsable"),
                    Prioridad           = Texto(r, "prioridad"),
                    Bloqueos            = Ent(r, "bloqueos"),
                    Excepciones         = Ent(r, "excepciones"),
                    MotivoBloqueo       = Texto(r, "motivo_bloqueo"),
                    Sla                 = Sla(r),
                    DocumentosFaltantes = Ent(r, "documentos_faltantes"),
                    ProximaAccion       = Texto(r, "proxima_accion"),
                    EtapaAvanzaDesdeExpediente = Bool(r, "etapa_manual"),
                    FechaCreacion       = FechaHora(r, "fecha_creacion"),
                    FechaCierre         = FechaHora(r, "fecha_cierre"),
                    Permisos            = new PermisosExpedienteDto(
                        Bool(r, "puede_adjuntar"), Bool(r, "puede_resolver"), Bool(r, "puede_reasignar"), Bool(r, "puede_avanzar")),
                };

                var etapas = await LeerListaAsync(r, x => new EtapaIndicadorDto(
                    Ent(x, "orden"), Texto(x, "etapa") ?? "", Texto(x, "nombre") ?? "", Texto(x, "estado") ?? "",
                    FechaHora(x, "inicio"), FechaHora(x, "fin"), Texto(x, "responsable")), ct);
                var bloqueos = await LeerListaAsync(r, LeerBloqueo, ct);
                var validaciones = await LeerListaAsync(r, Validacion, ct);
                var actividad = await LeerListaAsync(r, Evento, ct);

                return new RespuestaDto<DetalleExpedienteDto>(2, mensaje,
                    new DetalleExpedienteDto(resumen, etapas, bloqueos, validaciones, actividad));
            },
            ct);

    private static BloqueoExpedienteDto LeerBloqueo(MySqlDataReader x) => new(
        EnteroLargo(x, "id_bloqueador"), Texto(x, "clase") ?? "", Texto(x, "descripcion") ?? "", Texto(x, "tipo"),
        Texto(x, "etapa"), Texto(x, "tipo_documental"), Texto(x, "impacto"), Bool(x, "critico"), Texto(x, "origen_tipo"),
        EnteroLargoNulo(x, "id_origen"), EnteroLargoNulo(x, "id_responsable"), Texto(x, "responsable"),
        FechaHora(x, "fecha_registro"), Ent(x, "minutos_desde"));

    public Task<RespuestaDto<WorkflowExpedienteDto>> ObtenerWorkflowAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerWorkflowExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<WorkflowExpedienteDto>(3, "No se pudo leer el expediente.");
                var resumen = new ResumenWorkflowExpedienteDto(
                    EnteroLargo(r, "id_expediente"), Texto(r, "numero") ?? "", Texto(r, "estado") ?? "", Texto(r, "etapa") ?? "",
                    Texto(r, "etapa_nombre"), Ent(r, "progreso"), Texto(r, "razon_social"), Texto(r, "ruc"), Texto(r, "numero_rq"),
                    Texto(r, "propuesta"), Texto(r, "numeros_oc"), Texto(r, "numeros_os"), Texto(r, "numeros_om"),
                    Texto(r, "tipo_servicio"));

                var etapas = await LeerListaAsync(r, x => new EtapaWorkflowDto(
                    Ent(x, "orden"), Texto(x, "etapa") ?? "", Texto(x, "nombre") ?? "", Texto(x, "estado") ?? "",
                    Texto(x, "area"), Texto(x, "area_nombre"), EnteroLargoNulo(x, "id_responsable"), Texto(x, "responsable"),
                    FechaHora(x, "inicio"), FechaHora(x, "fin"), DecimalNulo(x, "horas_espera"), DecimalNulo(x, "horas_proceso"),
                    EntNulo(x, "sla_horas"), BoolNulo(x, "cumple_sla"), Texto(x, "resultado")), ct);

                var alertas = await LeerListaAsync(r, x => new AlertaBloqueoDto(
                    EnteroLargo(x, "id_bloqueador"), Texto(x, "descripcion") ?? "", Texto(x, "tipo_documental"),
                    Texto(x, "impacto"), Texto(x, "etapa"), FechaHora(x, "fecha_registro")), ct);
                var eventos = await LeerListaAsync(r, Evento, ct);

                return new RespuestaDto<WorkflowExpedienteDto>(2, mensaje,
                    new WorkflowExpedienteDto(resumen, etapas, alertas.FirstOrDefault(), eventos));
            },
            ct);

    // ── HU-31 Documentos ─────────────────────────────────────────────────────

    public Task<RespuestaDto<DocumentosExpedienteDto>> ObtenerDocumentosAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDocumentosExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DocumentosExpedienteDto>(3, "No se pudo leer el expediente.");
                long   id      = EnteroLargo(r, "id_expediente");
                string numero  = Texto(r, "numero") ?? "";
                string? razon  = Texto(r, "razon_social");
                string? ruc    = Texto(r, "ruc");
                bool   adjunta = Bool(r, "puede_adjuntar");

                var categorias = await LeerListaAsync(r, x => new CategoriaDocumentoDto(
                    Texto(x, "codigo") ?? "", Texto(x, "nombre") ?? "", Ent(x, "cantidad")), ct);
                var documentos = await LeerListaAsync(r, x => new DocumentoExpedienteDto(
                    Texto(x, "clave") ?? "", Texto(x, "nombre") ?? "", Texto(x, "nombre_archivo"), Texto(x, "tipo"),
                    Texto(x, "categoria") ?? "", Texto(x, "origen"), Texto(x, "etapa"), Texto(x, "etapa_nombre"),
                    Ent(x, "version"), Texto(x, "estado") ?? "", FechaHora(x, "fecha"), EnteroLargoNulo(x, "id_usuario"),
                    Texto(x, "usuario"), EnteroLargoNulo(x, "tamano_bytes"), Texto(x, "tipo_contenido"), Texto(x, "descripcion"),
                    Texto(x, "visibilidad"), Bool(x, "es_interno"), Bool(x, "descargable")), ct);
                var tipos = await LeerListaAsync(r, x => new TipoDocumentoExpedienteDto(
                    Ent(x, "id"), Texto(x, "nombre") ?? "", Texto(x, "codigo"), Texto(x, "categoria")), ct);
                var etapas = await LeerListaAsync(r, Opcion, ct);
                var visibilidades = await LeerListaAsync(r, x => new VisibilidadDocumentoDto(
                    Ent(x, "id"), Texto(x, "nombre") ?? "", Texto(x, "codigo"), Texto(x, "tipo") ?? ""), ct);

                return new RespuestaDto<DocumentosExpedienteDto>(2, mensaje,
                    new DocumentosExpedienteDto(id, numero, razon, ruc, adjunta, categorias, documentos, tipos, etapas, visibilidades));
            },
            ct);

    public Task<RespuestaDto<UbicacionArchivoExpedienteDto>> ObtenerArchivoAsync(long idExpediente, string clave, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerArchivoExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
                p.AddWithValue("p_clave",         clave);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<UbicacionArchivoExpedienteDto>(3, "No se pudo leer el documento.");
                return new RespuestaDto<UbicacionArchivoExpedienteDto>(2, mensaje, new UbicacionArchivoExpedienteDto(
                    Texto(r, "ruta"), Texto(r, "nombre_archivo") ?? "documento", Texto(r, "tipo_contenido"),
                    EnteroLargoNulo(r, "id_propuesta")));
            },
            ct);

    public Task<RespuestaDto<IReadOnlyList<ArchivoExportacionExpedienteDto>>> ObtenerArchivosExportacionAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerArchivosExportacionExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
            },
            async (r, mensaje) =>
            {
                var archivos = await LeerListaAsync(r, x => new ArchivoExportacionExpedienteDto(
                    Texto(x, "clave") ?? "", Texto(x, "categoria") ?? "", Texto(x, "carpeta") ?? "Documentos",
                    Texto(x, "nombre_archivo") ?? "documento", Ent(x, "version"), Texto(x, "estado") ?? "",
                    Texto(x, "ruta"), EnteroLargoNulo(x, "id_propuesta")), ct);
                return new RespuestaDto<IReadOnlyList<ArchivoExportacionExpedienteDto>>(2, mensaje, archivos);
            },
            ct);

    public Task<RespuestaDto<DocumentoAdjuntadoDto>> AdjuntarDocumentoAsync(
        long idExpediente, AdjuntarDocumentoExpedienteDto d, string? ruta, string? nombreArchivo, long? tamano,
        string? tipoContenido, string? hash, bool soloValidar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AdjuntarDocumentoExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_expediente",     idExpediente);
                p.AddWithValue("p_id_tipo_documento", Valor(d.IdTipoDocumento));
                p.AddWithValue("p_etapa",             Valor(d.Etapa));
                p.AddWithValue("p_nombre",            Valor(d.Nombre));
                p.AddWithValue("p_descripcion",       Valor(d.Descripcion));
                p.AddWithValue("p_id_visibilidad",    Valor(d.IdVisibilidad));
                p.AddWithValue("p_ruta",              Valor(ruta));
                p.AddWithValue("p_nombre_archivo",    Valor(nombreArchivo));
                p.AddWithValue("p_tamano",            Valor(tamano));
                p.AddWithValue("p_tipo_contenido",    Valor(tipoContenido));
                p.AddWithValue("p_hash",              Valor(hash));
                p.AddWithValue("p_solo_validar",      Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                if (soloValidar) return new RespuestaDto<DocumentoAdjuntadoDto>(2, mensaje);
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<DocumentoAdjuntadoDto>(3, "No se pudo leer el documento registrado.");
                return new RespuestaDto<DocumentoAdjuntadoDto>(2, mensaje, new DocumentoAdjuntadoDto(
                    EnteroLargo(r, "id_documento"), Texto(r, "clave") ?? "", Ent(r, "version"), Texto(r, "nombre") ?? "",
                    Texto(r, "tipo"), Texto(r, "etapa"), Texto(r, "etapa_nombre")));
            },
            ct);

    // ── HU-32 Bloqueos y excepciones ─────────────────────────────────────────

    public Task<RespuestaDto<BloqueoRegistradoDto>> RegistrarBloqueoAsync(long idExpediente, RegistrarBloqueoExpedienteDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarBloqueoExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_expediente",   idExpediente);
                p.AddWithValue("p_clase",           Valor(d.Clase));
                p.AddWithValue("p_tipo",            Valor(d.Tipo));
                p.AddWithValue("p_id_motivo",       Valor(d.IdMotivo));
                p.AddWithValue("p_descripcion",     Valor(d.Descripcion));
                p.AddWithValue("p_tipo_documental", Valor(d.TipoDocumental));
                p.AddWithValue("p_impacto",         Valor(d.Impacto));
                p.AddWithValue("p_critico",         d.Critico is null ? DBNull.Value : Bit(d.Critico.Value));
                p.AddWithValue("p_id_responsable",  Valor(d.IdResponsable));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<BloqueoRegistradoDto>(3, "No se pudo leer el registro.");
                return new RespuestaDto<BloqueoRegistradoDto>(2, mensaje, new BloqueoRegistradoDto(
                    EnteroLargo(r, "id_bloqueador"), Texto(r, "clase") ?? "", Texto(r, "etapa"), Texto(r, "estado_expediente"),
                    Ent(r, "notificados")));
            },
            ct);

    public Task<RespuestaDto<PreparacionResolucionBloqueoDto>> PrepararResolucionBloqueoAsync(long idExpediente, long idBloqueador, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararResolucionBloqueo",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
                p.AddWithValue("p_id_bloqueador", idBloqueador);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<PreparacionResolucionBloqueoDto>(3, "No se pudo leer el bloqueo.");
                var contexto = new ContextoBloqueoDto
                {
                    IdBloqueador     = EnteroLargo(r, "id_bloqueador"),
                    Clase            = Texto(r, "clase") ?? "",
                    IdExpediente     = EnteroLargo(r, "id_expediente"),
                    Numero           = Texto(r, "numero") ?? "",
                    RazonSocial      = Texto(r, "razon_social"),
                    Ruc              = Texto(r, "ruc"),
                    Etapa            = Texto(r, "etapa"),
                    EtapaNombre      = Texto(r, "etapa_nombre"),
                    Descripcion      = Texto(r, "descripcion") ?? "",
                    Tipo             = Texto(r, "tipo"),
                    TipoDocumental   = Texto(r, "tipo_documental"),
                    Impacto          = Texto(r, "impacto"),
                    Critico          = Bool(r, "critico"),
                    Motivo           = Texto(r, "motivo"),
                    IdResponsable    = EnteroLargoNulo(r, "id_responsable"),
                    Responsable      = Texto(r, "responsable"),
                    FechaDeteccion   = FechaHora(r, "fecha_deteccion"),
                    OrigenTipo       = Texto(r, "origen_tipo"),
                    Tecnico          = Texto(r, "tecnico"),
                    FechaVencimiento = Fecha(r, "fecha_vencimiento"),
                    EstadoDocumento  = Texto(r, "estado_documento"),
                    SeResuelveEnOc   = Bool(r, "se_resuelve_en_oc"),
                };
                var opciones = await LeerListaAsync(r, OpcionId, ct);
                return new RespuestaDto<PreparacionResolucionBloqueoDto>(2, mensaje, new PreparacionResolucionBloqueoDto(contexto, opciones));
            },
            ct);

    public Task<RespuestaDto<BloqueoResueltoDto>> ResolverBloqueoAsync(
        long idExpediente, long idBloqueador, ResolverBloqueoExpedienteDto d, string? ruta, string? nombreArchivo, long? tamano,
        string? tipoContenido, string? hash, bool soloValidar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverBloqueoExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_expediente",  idExpediente);
                p.AddWithValue("p_id_bloqueador",  idBloqueador);
                p.AddWithValue("p_id_opcion",      Valor(d.IdOpcion));
                p.AddWithValue("p_sustento",       Valor(d.Sustento));
                p.AddWithValue("p_ruta",           Valor(ruta));
                p.AddWithValue("p_nombre_archivo", Valor(nombreArchivo));
                p.AddWithValue("p_tamano",         Valor(tamano));
                p.AddWithValue("p_tipo_contenido", Valor(tipoContenido));
                p.AddWithValue("p_hash",           Valor(hash));
                p.AddWithValue("p_solo_validar",   Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                if (soloValidar) return new RespuestaDto<BloqueoResueltoDto>(2, mensaje);
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<BloqueoResueltoDto>(3, "No se pudo leer el resultado.");
                return new RespuestaDto<BloqueoResueltoDto>(2, mensaje, new BloqueoResueltoDto(
                    EnteroLargo(r, "id_bloqueador"), Texto(r, "clase") ?? "", Texto(r, "estado_expediente"),
                    EnteroLargo(r, "id_documento"), Texto(r, "clave_documento") ?? "", Ent(r, "notificados")));
            },
            ct);

    // ── HU-33 Historial y reasignación ───────────────────────────────────────

    public Task<RespuestaDto<HistorialExpedienteDto>> ObtenerHistorialAsync(long idExpediente, FiltrosHistorialExpedienteDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerHistorialExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_expediente",     idExpediente);
                p.AddWithValue("p_tipo_evento",       Valor(f.TipoEvento));
                p.AddWithValue("p_id_usuario_evento", Valor(f.IdUsuario));
                p.AddWithValue("p_etapa",             Valor(f.Etapa));
                p.AddWithValue("p_desde",             f.Desde is { } desde ? desde.Date : DBNull.Value);
                p.AddWithValue("p_hasta",             f.Hasta is { } hasta ? hasta.Date : DBNull.Value);
                p.AddWithValue("p_exportar",          Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<HistorialExpedienteDto>(3, "No se pudo leer el expediente.");
                long    id     = EnteroLargo(r, "id_expediente");
                string  numero = Texto(r, "numero") ?? "";
                string? razon  = Texto(r, "razon_social");
                string? ruc    = Texto(r, "ruc");

                var eventos  = await LeerListaAsync(r, Evento, ct);
                var tipos    = await LeerListaAsync(r, Opcion, ct);
                var usuarios = await LeerListaAsync(r, x => new UsuarioFiltroDto(EnteroLargo(x, "id_usuario"), Texto(x, "nombre") ?? ""), ct);
                var etapas   = await LeerListaAsync(r, Opcion, ct);

                return new RespuestaDto<HistorialExpedienteDto>(2, mensaje,
                    new HistorialExpedienteDto(id, numero, razon, ruc, eventos, tipos, usuarios, etapas));
            },
            ct);

    public Task<RespuestaDto<PreparacionReasignacionExpedienteDto>> PrepararReasignacionAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararReasignacionExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<PreparacionReasignacionExpedienteDto>(3, "No se pudo leer el expediente.");
                var datos = new DatosReasignacionExpedienteDto(
                    EnteroLargo(r, "id_expediente"), Texto(r, "numero") ?? "", Texto(r, "etapa") ?? "", Texto(r, "etapa_nombre"),
                    EnteroLargoNulo(r, "id_responsable"), Texto(r, "responsable"), Texto(r, "cargo_responsable"),
                    Texto(r, "area"), Texto(r, "area_nombre"),
                    new SlaExpedienteDto(null, EntNulo(r, "sla_horas"), FechaHora(r, "fecha_limite"), Texto(r, "sla_estado"),
                                         EntNulo(r, "sla_minutos_restantes")),
                    Texto(r, "nota_impacto") ?? "");
                var motivos = await LeerListaAsync(r, OpcionId, ct);
                return new RespuestaDto<PreparacionReasignacionExpedienteDto>(2, mensaje, new PreparacionReasignacionExpedienteDto(datos, motivos));
            },
            ct);

    public Task<RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>> BuscarResponsablesAsync(long idExpediente, string? busqueda, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_BuscarResponsablesExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
                p.AddWithValue("p_busqueda",      Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                var lista = await LeerListaAsync(r, x => new CandidatoResponsableDto(
                    EnteroLargo(x, "id_usuario"), Texto(x, "nombre") ?? "", Texto(x, "correo"), Texto(x, "cargo"),
                    Texto(x, "area"), Texto(x, "area_nombre"), Texto(x, "rol_sistema")), ct);
                return new RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>(2, mensaje, lista);
            },
            ct);

    public Task<RespuestaDto<ReasignacionExpedienteDto>> ReasignarResponsableAsync(long idExpediente, ReasignarResponsableExpedienteDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ReasignarResponsableExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
                p.AddWithValue("p_id_nuevo",      Valor(d.IdNuevoResponsable));
                p.AddWithValue("p_id_motivo",     Valor(d.IdMotivo));
                p.AddWithValue("p_comentario",    Valor(d.Comentario));
                p.AddWithValue("p_gestion_sla",   Valor(d.GestionSla));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ReasignacionExpedienteDto>(3, "No se pudo leer el resultado.");
                return new RespuestaDto<ReasignacionExpedienteDto>(2, mensaje, new ReasignacionExpedienteDto
                {
                    IdExpediente      = EnteroLargo(r, "id_expediente"),
                    Numero            = Texto(r, "numero") ?? "",
                    Cliente           = Texto(r, "cliente"),
                    Etapa             = Texto(r, "etapa"),
                    EtapaNombre       = Texto(r, "etapa_nombre"),
                    IdResponsable     = EnteroLargo(r, "id_responsable"),
                    Responsable       = Texto(r, "responsable") ?? "",
                    CorreoResponsable = Texto(r, "correo_responsable"),
                    Area              = Texto(r, "area"),
                    Motivo            = Texto(r, "motivo"),
                    Comentario        = Texto(r, "comentario"),
                    GestionSla        = Texto(r, "gestion_sla"),
                    FechaLimite       = FechaHora(r, "fecha_limite"),
                    ReasignadoPor     = Texto(r, "reasignado_por"),
                    Notificados       = Ent(r, "notificados"),
                });
            },
            ct);

    // ── HU-34 Avance de etapa ────────────────────────────────────────────────

    public Task<RespuestaDto<PreparacionAvanceExpedienteDto>> PrepararAvanceAsync(long idExpediente, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararAvanceExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<PreparacionAvanceExpedienteDto>(3, "No se pudo leer el expediente.");
                var datos = new DatosAvanceExpedienteDto
                {
                    IdExpediente         = EnteroLargo(r, "id_expediente"),
                    Numero               = Texto(r, "numero") ?? "",
                    Etapa                = Texto(r, "etapa") ?? "",
                    EtapaNombre          = Texto(r, "etapa_nombre"),
                    Estado               = Texto(r, "estado") ?? "",
                    IdResponsable        = EnteroLargoNulo(r, "id_responsable"),
                    Responsable          = Texto(r, "responsable"),
                    Area                 = Texto(r, "area"),
                    AreaNombre           = Texto(r, "area_nombre"),
                    SiguienteEtapa       = Texto(r, "siguiente_etapa"),
                    SiguienteEtapaNombre = Texto(r, "siguiente_etapa_nombre"),
                    AreaSiguiente        = Texto(r, "area_siguiente"),
                    AreaSiguienteNombre  = Texto(r, "area_siguiente_nombre"),
                    Listo                = Bool(r, "listo"),
                    PuedeAvanzar         = Bool(r, "puede_avanzar"),
                    Mensaje              = Texto(r, "mensaje"),
                    IdBloqueoPendiente   = EnteroLargoNulo(r, "id_bloqueo_pendiente"),
                    FechaRevision        = FechaHora(r, "fecha_revision"),
                    RevisadoPor          = Texto(r, "revisado_por"),
                };
                var validaciones = await LeerListaAsync(r, Validacion, ct);
                return new RespuestaDto<PreparacionAvanceExpedienteDto>(2, mensaje, new PreparacionAvanceExpedienteDto(datos, validaciones));
            },
            ct);

    public Task<RespuestaDto<AvanceExpedienteDto>> AvanzarEtapaAsync(long idExpediente, string? comentario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AvanzarEtapaExpediente",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_expediente", idExpediente);
                p.AddWithValue("p_comentario",    Valor(comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<AvanceExpedienteDto>(3, "No se pudo leer el resultado.");
                return new RespuestaDto<AvanceExpedienteDto>(2, mensaje, new AvanceExpedienteDto(
                    EnteroLargo(r, "id_expediente"), Texto(r, "numero") ?? "", Texto(r, "etapa_anterior") ?? "",
                    Texto(r, "etapa_actual") ?? "", Texto(r, "etapa_nombre"), Texto(r, "area_responsable"),
                    EntNulo(r, "sla_horas"), FechaHora(r, "fecha_limite"), Ent(r, "notificados")));
            },
            ct);
}
