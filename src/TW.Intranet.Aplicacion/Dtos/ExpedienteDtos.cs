namespace TW.Intranet.Aplicacion.Dtos;

// ══════════════════════ Expediente Digital (HU-29 a HU-34) ══════════════════════

/// <summary>Opción de un select (catálogo tal cual).</summary>
public record OpcionExpedienteDto(string Codigo, string Nombre);

/// <summary>Opción de un select con id numérico (catálogos de tabla_maestra).</summary>
public record OpcionIdExpedienteDto(int Id, string Nombre, string? Codigo);

// ── HU-29 Bandeja ────────────────────────────────────────────────────────────

public record FiltrosBandejaExpedientesDto
{
    /// <summary>abiertos (defecto), todos, activo, listo_para_avanzar, bloqueado, con_excepcion, sla_vencido, pendiente_cierre, cerrado.</summary>
    public string? Estado    { get; init; }
    public string? Etapa     { get; init; }
    public long?   IdCliente { get; init; }
    public string? Area      { get; init; }
    public string? Busqueda  { get; init; }
    public int     Pagina    { get; init; } = 1;
    public int     PorPagina { get; init; } = 10;
}

public record TarjetasExpedientesDto(
    int Activos, int ListosParaAvanzar, int Bloqueados, int ConExcepcion, int SlaVencidos, int PendientesCierre);

public record SlaExpedienteDto(
    DateTime? InicioEtapa, int? Horas, DateTime? FechaLimite, string? Estado, int? MinutosRestantes);

public record FilaExpedienteDto
{
    public long      IdExpediente     { get; init; }
    public string    Numero           { get; init; } = "";
    public string    Estado           { get; init; } = "";
    public string    Etapa            { get; init; } = "";
    public string?   EtapaNombre      { get; init; }
    public int       Progreso         { get; init; }
    public long?     IdCliente        { get; init; }
    public string?   RazonSocial      { get; init; }
    public string?   Ruc              { get; init; }
    public long?     IdRequerimiento  { get; init; }
    public string?   NumeroRq         { get; init; }
    public long?     IdPropuesta      { get; init; }
    public string?   Propuesta        { get; init; }
    public string?   NumerosOc        { get; init; }
    public string?   NumerosOs        { get; init; }
    public string?   NumerosOm        { get; init; }
    public string?   TipoServicio     { get; init; }
    public string?   Area             { get; init; }
    public string?   AreaNombre       { get; init; }
    public long?     IdResponsable    { get; init; }
    public string?   Responsable      { get; init; }
    public string?   Prioridad        { get; init; }
    public int       Bloqueos         { get; init; }
    public int       Excepciones      { get; init; }
    public string?   MotivoBloqueo    { get; init; }
    public SlaExpedienteDto Sla       { get; init; } = new(null, null, null, null, null);
    public DateTime? FechaCreacion    { get; init; }
}

public record ClienteFiltroExpedienteDto(long IdCliente, string RazonSocial, string? Ruc);

public record BandejaExpedientesDto(
    TarjetasExpedientesDto              Tarjetas,
    IReadOnlyList<FilaExpedienteDto>    Filas,
    int                                 Total,
    int                                 Pagina,
    int                                 PorPagina,
    IReadOnlyList<OpcionExpedienteDto>  Estados,
    IReadOnlyList<OpcionExpedienteDto>  Etapas,
    IReadOnlyList<ClienteFiltroExpedienteDto> Clientes,
    IReadOnlyList<OpcionExpedienteDto>  Areas);

// ── HU-30 Detalle y workflow ─────────────────────────────────────────────────

public record PermisosExpedienteDto(bool PuedeAdjuntar, bool PuedeResolver, bool PuedeReasignar, bool PuedeAvanzar);

public record ResumenExpedienteDto
{
    public long      IdExpediente        { get; init; }
    public string    Numero              { get; init; } = "";
    public string    Estado              { get; init; } = "";
    public string    Etapa               { get; init; } = "";
    public string?   EtapaNombre         { get; init; }
    public int       Progreso            { get; init; }
    public long?     IdCliente           { get; init; }
    public string?   RazonSocial         { get; init; }
    public string?   Ruc                 { get; init; }
    public long?     IdRequerimiento     { get; init; }
    public string?   NumeroRq            { get; init; }
    public string?   DescripcionRq       { get; init; }
    public long?     IdPropuesta         { get; init; }
    public string?   Propuesta           { get; init; }
    public string?   NumerosOc           { get; init; }
    public string?   NumerosOs           { get; init; }
    public string?   NumerosOm           { get; init; }
    public string?   TipoServicio        { get; init; }
    public int       Equipos             { get; init; }
    public string?   Ubicacion           { get; init; }
    public string?   Area                { get; init; }
    public string?   AreaNombre          { get; init; }
    public long?     IdResponsable       { get; init; }
    public string?   Responsable         { get; init; }
    public string?   Prioridad           { get; init; }
    public int       Bloqueos            { get; init; }
    public int       Excepciones         { get; init; }
    public string?   MotivoBloqueo       { get; init; }
    public SlaExpedienteDto Sla          { get; init; } = new(null, null, null, null, null);
    public int       DocumentosFaltantes { get; init; }
    public string?   ProximaAccion       { get; init; }
    public bool      EtapaAvanzaDesdeExpediente { get; init; }
    public DateTime? FechaCreacion       { get; init; }
    public DateTime? FechaCierre         { get; init; }
    public PermisosExpedienteDto Permisos { get; init; } = new(false, false, false, false);
}

/// <summary>Etapa del indicador de progreso: completado, en_curso, bloqueado, pendiente, cancelado, no_aplica.</summary>
public record EtapaIndicadorDto(int Orden, string Etapa, string Nombre, string Estado, DateTime? Inicio, DateTime? Fin, string? Responsable);

public record BloqueoExpedienteDto(
    long      IdBloqueador,
    string    Clase,
    string    Descripcion,
    string?   Tipo,
    string?   Etapa,
    string?   TipoDocumental,
    string?   Impacto,
    bool      Critico,
    string?   OrigenTipo,
    long?     IdOrigen,
    long?     IdResponsable,
    string?   Responsable,
    DateTime? FechaRegistro,
    int       MinutosDesde);

public record ValidacionEtapaDto(
    int Orden, string Codigo, string Descripcion, bool Cumple, bool Critico, bool EsDocumento, string? Detalle, string? AccionSugerida);

public record EventoExpedienteDto(
    DateTime  Fecha,
    string?   TipoEvento,
    string?   Accion,
    string?   Titulo,
    string?   Descripcion,
    string?   Etapa,
    string?   EtapaNombre,
    long?     IdUsuario,
    string    Usuario,
    string?   Entidad,
    string?   Referencia,
    bool      Urgente);

public record DetalleExpedienteDto(
    ResumenExpedienteDto                Resumen,
    IReadOnlyList<EtapaIndicadorDto>    Etapas,
    IReadOnlyList<BloqueoExpedienteDto> BloqueosAbiertos,
    IReadOnlyList<ValidacionEtapaDto>   Validaciones,
    IReadOnlyList<EventoExpedienteDto>  ActividadReciente);

public record ResumenWorkflowExpedienteDto(
    long IdExpediente, string Numero, string Estado, string Etapa, string? EtapaNombre, int Progreso,
    string? RazonSocial, string? Ruc, string? NumeroRq, string? Propuesta, string? NumerosOc, string? NumerosOs,
    string? NumerosOm, string? TipoServicio);

public record EtapaWorkflowDto(
    int       Orden,
    string    Etapa,
    string    Nombre,
    string    Estado,
    string?   Area,
    string?   AreaNombre,
    long?     IdResponsable,
    string?   Responsable,
    DateTime? Inicio,
    DateTime? Fin,
    decimal?  HorasEspera,
    decimal?  HorasProceso,
    int?      SlaHoras,
    bool?     CumpleSla,
    string?   Resultado);

public record AlertaBloqueoDto(long IdBloqueador, string Descripcion, string? TipoDocumental, string? Impacto, string? Etapa, DateTime? FechaRegistro);

public record WorkflowExpedienteDto(
    ResumenWorkflowExpedienteDto        Resumen,
    IReadOnlyList<EtapaWorkflowDto>     Etapas,
    AlertaBloqueoDto?                   AlertaBloqueo,
    IReadOnlyList<EventoExpedienteDto>  Eventos);

// ── HU-31 Documentos ─────────────────────────────────────────────────────────

public record CategoriaDocumentoDto(string Codigo, string Nombre, int Cantidad);

public record DocumentoExpedienteDto(
    string    Clave,
    string    Nombre,
    string?   NombreArchivo,
    string?   Tipo,
    string    Categoria,
    string?   Origen,
    string?   Etapa,
    string?   EtapaNombre,
    int       Version,
    string    Estado,
    DateTime? Fecha,
    long?     IdUsuario,
    string?   Usuario,
    long?     TamanoBytes,
    string?   TipoContenido,
    string?   Descripcion,
    string?   Visibilidad,
    bool      EsInterno,
    bool      Descargable);

public record TipoDocumentoExpedienteDto(int Id, string Nombre, string? Codigo, string? Categoria);

public record VisibilidadDocumentoDto(int Id, string Nombre, string? Codigo, string Tipo);

public record DocumentosExpedienteDto(
    long   IdExpediente,
    string Numero,
    string? RazonSocial,
    string? Ruc,
    bool   PuedeAdjuntar,
    IReadOnlyList<CategoriaDocumentoDto>      Categorias,
    IReadOnlyList<DocumentoExpedienteDto>     Documentos,
    IReadOnlyList<TipoDocumentoExpedienteDto> TiposDocumento,
    IReadOnlyList<OpcionExpedienteDto>        Etapas,
    IReadOnlyList<VisibilidadDocumentoDto>    Visibilidades);

/// <summary>Datos del formulario "Adjuntar documento interno" (multipart, el archivo va aparte).</summary>
public record AdjuntarDocumentoExpedienteDto
{
    public int?    IdTipoDocumento { get; init; }
    public string? Etapa           { get; init; }
    public string? Nombre          { get; init; }
    public string? Descripcion     { get; init; }
    /// <summary>VISIBILIDAD_DOCUMENTO: 1 interno, 2 Comercial, 3 Operaciones, 4 SSOMA.</summary>
    public int?    IdVisibilidad   { get; init; }
}

public record DocumentoAdjuntadoDto(long IdDocumento, string Clave, int Version, string Nombre, string? Tipo, string? Etapa, string? EtapaNombre);

/// <summary>Ubicación de un archivo del expediente: ruta en el almacenamiento o propuesta cuyo PDF se genera.</summary>
public record UbicacionArchivoExpedienteDto(string? Ruta, string NombreArchivo, string? TipoContenido, long? IdPropuesta);

public record ArchivoExportacionExpedienteDto(
    string Clave, string Categoria, string Carpeta, string NombreArchivo, int Version, string Estado, string? Ruta, long? IdPropuesta);

/// <summary>Archivo binario generado (XLSX, ZIP).</summary>
public record ArchivoGeneradoDto(byte[] Contenido, string NombreArchivo, string TipoContenido);

// ── HU-32 Bloqueos y excepciones ─────────────────────────────────────────────

public record RegistrarBloqueoExpedienteDto
{
    /// <summary>bloqueo | excepcion</summary>
    public string? Clase          { get; init; }
    /// <summary>documento_faltante | ssoma | cobertura_oc | sin_aprobacion | otro</summary>
    public string? Tipo           { get; init; }
    public int?    IdMotivo       { get; init; }
    public string? Descripcion    { get; init; }
    public string? TipoDocumental { get; init; }
    public string? Impacto        { get; init; }
    public bool?   Critico        { get; init; }
    public long?   IdResponsable  { get; init; }
}

public record BloqueoRegistradoDto(long IdBloqueador, string Clase, string? Etapa, string? EstadoExpediente, int Notificados);

public record ContextoBloqueoDto
{
    public long      IdBloqueador     { get; init; }
    public string    Clase            { get; init; } = "";
    public long      IdExpediente     { get; init; }
    public string    Numero           { get; init; } = "";
    public string?   RazonSocial      { get; init; }
    public string?   Ruc              { get; init; }
    public string?   Etapa            { get; init; }
    public string?   EtapaNombre      { get; init; }
    public string    Descripcion      { get; init; } = "";
    public string?   Tipo             { get; init; }
    public string?   TipoDocumental   { get; init; }
    public string?   Impacto          { get; init; }
    public bool      Critico          { get; init; }
    public string?   Motivo           { get; init; }
    public long?     IdResponsable    { get; init; }
    public string?   Responsable      { get; init; }
    public DateTime? FechaDeteccion   { get; init; }
    public string?   OrigenTipo       { get; init; }
    public string?   Tecnico          { get; init; }
    public string?   FechaVencimiento { get; init; }
    public string?   EstadoDocumento  { get; init; }
    /// <summary>true: viene de una OC observada y se resuelve revalidando la OC (no desde este modal).</summary>
    public bool      SeResuelveEnOc   { get; init; }
}

/// <summary>Opciones: tipos de resolución (bloqueo) o resultados de cierre (excepción).</summary>
public record PreparacionResolucionBloqueoDto(ContextoBloqueoDto Contexto, IReadOnlyList<OpcionIdExpedienteDto> Opciones);

/// <summary>Formulario de resolución (multipart; la evidencia va aparte, en el campo "archivo").</summary>
public record ResolverBloqueoExpedienteDto
{
    /// <summary>Tipo de resolución (bloqueo) o resultado de cierre (excepción).</summary>
    public int?    IdOpcion { get; init; }
    /// <summary>Comentario (bloqueo, opcional) o sustento de cierre (excepción, obligatorio).</summary>
    public string? Sustento { get; init; }
}

public record BloqueoResueltoDto(long IdBloqueador, string Clase, string? EstadoExpediente, long IdDocumento, string ClaveDocumento, int Notificados);

// ── HU-33 Historial y reasignación ───────────────────────────────────────────

public record FiltrosHistorialExpedienteDto
{
    public string?   TipoEvento { get; init; }
    public long?     IdUsuario  { get; init; }
    public string?   Etapa      { get; init; }
    public DateTime? Desde      { get; init; }
    public DateTime? Hasta      { get; init; }
}

public record UsuarioFiltroDto(long IdUsuario, string Nombre);

public record HistorialExpedienteDto(
    long   IdExpediente,
    string Numero,
    string? RazonSocial,
    string? Ruc,
    IReadOnlyList<EventoExpedienteDto>  Eventos,
    IReadOnlyList<OpcionExpedienteDto>  TiposEvento,
    IReadOnlyList<UsuarioFiltroDto>     Usuarios,
    IReadOnlyList<OpcionExpedienteDto>  Etapas);

public record DatosReasignacionExpedienteDto(
    long      IdExpediente,
    string    Numero,
    string    Etapa,
    string?   EtapaNombre,
    long?     IdResponsable,
    string?   Responsable,
    string?   CargoResponsable,
    string?   Area,
    string?   AreaNombre,
    SlaExpedienteDto Sla,
    string    NotaImpacto);

public record PreparacionReasignacionExpedienteDto(DatosReasignacionExpedienteDto Datos, IReadOnlyList<OpcionIdExpedienteDto> Motivos);

public record CandidatoResponsableDto(long IdUsuario, string Nombre, string? Correo, string? Cargo, string? Area, string? AreaNombre, string? Rol);

public record ReasignarResponsableExpedienteDto
{
    public long?   IdNuevoResponsable { get; init; }
    public int?    IdMotivo           { get; init; }
    public string? Comentario         { get; init; }
    /// <summary>mantener (defecto) | reiniciar</summary>
    public string? GestionSla         { get; init; }
}

public record ReasignacionExpedienteDto
{
    public long      IdExpediente      { get; init; }
    public string    Numero            { get; init; } = "";
    public string?   Cliente           { get; init; }
    public string?   Etapa             { get; init; }
    public string?   EtapaNombre       { get; init; }
    public long      IdResponsable     { get; init; }
    public string    Responsable       { get; init; } = "";
    public string?   CorreoResponsable { get; init; }
    public string?   Area              { get; init; }
    public string?   Motivo            { get; init; }
    public string?   Comentario        { get; init; }
    public string?   GestionSla        { get; init; }
    public DateTime? FechaLimite       { get; init; }
    public string?   ReasignadoPor     { get; init; }
    public int       Notificados       { get; init; }
    public bool      CorreoEnviado     { get; init; }
    public string?   CorreoError       { get; init; }
}

// ── HU-34 Avance de etapa ────────────────────────────────────────────────────

public record DatosAvanceExpedienteDto
{
    public long      IdExpediente          { get; init; }
    public string    Numero                { get; init; } = "";
    public string    Etapa                 { get; init; } = "";
    public string?   EtapaNombre           { get; init; }
    public string    Estado                { get; init; } = "";
    public long?     IdResponsable         { get; init; }
    public string?   Responsable           { get; init; }
    public string?   Area                  { get; init; }
    public string?   AreaNombre            { get; init; }
    public string?   SiguienteEtapa        { get; init; }
    public string?   SiguienteEtapaNombre  { get; init; }
    public string?   AreaSiguiente         { get; init; }
    public string?   AreaSiguienteNombre   { get; init; }
    public bool      Listo                 { get; init; }
    public bool      PuedeAvanzar          { get; init; }
    public string?   Mensaje               { get; init; }
    public long?     IdBloqueoPendiente    { get; init; }
    public DateTime? FechaRevision         { get; init; }
    public string?   RevisadoPor           { get; init; }
}

public record PreparacionAvanceExpedienteDto(DatosAvanceExpedienteDto Datos, IReadOnlyList<ValidacionEtapaDto> Validaciones);

public record AvanzarEtapaExpedienteDto
{
    public string? Comentario { get; init; }
}

public record AvanceExpedienteDto(
    long IdExpediente, string Numero, string EtapaAnterior, string EtapaActual, string? EtapaNombre,
    string? AreaResponsable, int? SlaHoras, DateTime? FechaLimite, int Notificados);
