namespace TW.Intranet.Aplicacion.Dtos;

// ══════════════════════ Expediente Digital (Sprint 4, HU-29 a HU-33) ══════════════════════
// El expediente es de consulta: nace con el RQ, las etapas avanzan solas y los bloqueos se resuelven en los módulos origen.

/// <summary>Opción de un select (catálogo tal cual).</summary>
public record OpcionExpedienteDto(string Codigo, string Nombre);

/// <summary>Opción de un select con id numérico (catálogos de tabla_maestra).</summary>
public record OpcionIdExpedienteDto(int Id, string Nombre, string? Codigo);

/// <summary>SLA de la etapa actual: en_plazo, en_riesgo o vencido.</summary>
public record SlaExpedienteDto(
    DateTime? InicioEtapa, int? Horas, DateTime? FechaLimite, string? Estado, int? MinutosRestantes);

/// <summary>Archivo binario generado (XLSX, PDF).</summary>
public record ArchivoGeneradoDto(byte[] Contenido, string NombreArchivo, string TipoContenido);

// ── HU-29 Bandeja ────────────────────────────────────────────────────────────

public record FiltrosBandejaExpedientesDto
{
    /// <summary>
    /// Tarjeta o estado global: abiertos (defecto, tarjeta "Expedientes Activos"), listo_para_avanzar, bloqueado,
    /// con_excepcion, sla_vencido, activo, cerrado o todos.
    /// </summary>
    public string?   Estado        { get; init; }
    public string?   Etapa         { get; init; }
    public long?     IdCliente     { get; init; }
    public string?   Area          { get; init; }
    /// <summary>Tipo de servicio de la propuesta, tal cual (opciones en TiposPropuesta).</summary>
    public string?   TipoPropuesta { get; init; }
    public DateTime? Desde         { get; init; }
    public DateTime? Hasta         { get; init; }
    /// <summary>en_plazo, en_riesgo o vencido.</summary>
    public string?   Sla           { get; init; }
    /// <summary>N.° RQ, N.° propuesta, cliente o RUC (también N.° de expediente, OC y OS/OM).</summary>
    public string?   Busqueda      { get; init; }
    public int       Pagina        { get; init; } = 1;
    public int       PorPagina     { get; init; } = 10;
}

public record TarjetasExpedientesDto(int Activos, int ListosParaAvanzar, int Bloqueados, int ConExcepcion, int SlaVencidos);

/// <summary>Fila de la tabla de 8 columnas: RQ, Propuesta, Cliente/RUC, OC (cantidad), OS/OM, Tipo de propuesta, Etapa, Estado.</summary>
public record FilaExpedienteDto
{
    public long      IdExpediente       { get; init; }
    public string    Numero             { get; init; } = "";
    public long?     IdRequerimiento    { get; init; }
    public string?   NumeroRq           { get; init; }
    public long?     IdPropuesta        { get; init; }
    public string?   NumeroPropuesta    { get; init; }
    public int?      VersionPropuesta   { get; init; }
    public string?   EstadoPropuesta    { get; init; }
    /// <summary>Otras propuestas del RQ (sub-texto "+N más").</summary>
    public int       PropuestasOtras    { get; init; }
    public long?     IdCliente          { get; init; }
    public string?   RazonSocial        { get; init; }
    public string?   Ruc                { get; init; }
    public int       CantidadOc         { get; init; }
    public string?   NumerosOc          { get; init; }
    /// <summary>Código de la OS (o de la OM si no hay OS); vacío si aún no se generó.</summary>
    public string?   NumeroOsOm         { get; init; }
    public string?   NumerosOs          { get; init; }
    public string?   NumerosOm          { get; init; }
    public string?   TipoPropuesta      { get; init; }
    public string    Etapa              { get; init; } = "";
    public string?   EtapaNombre        { get; init; }
    /// <summary>activo, bloqueado, con_excepcion o cerrado.</summary>
    public string    Estado             { get; init; } = "";
    public bool      ListoParaAvanzar   { get; init; }
    public int       Progreso           { get; init; }
    public string?   Area               { get; init; }
    public string?   AreaNombre         { get; init; }
    public long?     IdResponsable      { get; init; }
    public string?   Responsable        { get; init; }
    public long?     IdResponsableEtapa { get; init; }
    public string?   ResponsableEtapa   { get; init; }
    public int       Bloqueos           { get; init; }
    public int       Excepciones        { get; init; }
    public string?   MotivoBloqueo      { get; init; }
    public SlaExpedienteDto Sla         { get; init; } = new(null, null, null, null, null);
    public DateTime? FechaCreacion      { get; init; }
    public int       DiasTranscurridos  { get; init; }
}

public record ClienteFiltroExpedienteDto(long IdCliente, string RazonSocial, string? Ruc);

public record BandejaExpedientesDto(
    TarjetasExpedientesDto                     Tarjetas,
    IReadOnlyList<FilaExpedienteDto>           Filas,
    int                                        Total,
    int                                        Pagina,
    int                                        PorPagina,
    IReadOnlyList<OpcionExpedienteDto>         Estados,
    IReadOnlyList<OpcionExpedienteDto>         Etapas,
    IReadOnlyList<ClienteFiltroExpedienteDto>  Clientes,
    IReadOnlyList<OpcionExpedienteDto>         Areas,
    IReadOnlyList<OpcionExpedienteDto>         TiposPropuesta,
    IReadOnlyList<OpcionExpedienteDto>         EstadosSla);

// ── HU-30 Ficha: sección primaria, KPIs y tab Resumen ────────────────────────

public record CabeceraExpedienteDto
{
    public long      IdExpediente         { get; init; }
    public string    Numero               { get; init; } = "";
    /// <summary>Estado global: activo, bloqueado, con_excepcion o cerrado.</summary>
    public string    Estado               { get; init; } = "";
    public string    Etapa                { get; init; } = "";
    public string?   EtapaNombre          { get; init; }
    public bool      EtapaComercial       { get; init; }
    public int       Progreso             { get; init; }
    public long?     IdCliente            { get; init; }
    public string?   RazonSocial          { get; init; }
    public string?   Ruc                  { get; init; }
    public string?   AreaServicio         { get; init; }
    public string?   Area                 { get; init; }
    public string?   AreaNombre           { get; init; }
    public long?     IdResponsable        { get; init; }
    public string?   Responsable          { get; init; }
    public string?   CargoResponsable     { get; init; }
    public long?     IdResponsableEtapa   { get; init; }
    public string?   ResponsableEtapa     { get; init; }
    public long?     IdRequerimiento      { get; init; }
    public string?   NumeroRq             { get; init; }
    public long?     IdPropuesta          { get; init; }
    public string?   NumeroPropuesta      { get; init; }
    public int?      VersionPropuesta     { get; init; }
    public string?   EstadoPropuesta      { get; init; }
    public string?   TipoPropuesta        { get; init; }
    public decimal?  MontoTotal           { get; init; }
    public string?   Moneda               { get; init; }
    public string?   SimboloMoneda        { get; init; }
    public DateTime? FechaCreacion        { get; init; }
    public DateTime? FechaCierre          { get; init; }
    // KPIs
    public int       DiasTranscurridos    { get; init; }
    public SlaExpedienteDto Sla           { get; init; } = new(null, null, null, null, null);
    public int       DocumentosTotales    { get; init; }
    public int       BloqueosActivos      { get; init; }
    public int       ExcepcionesActivas   { get; init; }
    public string?   MotivoBloqueo        { get; init; }
    public bool      ListoParaAvanzar     { get; init; }
    // Próximo hito
    public string?   SiguienteEtapa       { get; init; }
    public string?   SiguienteEtapaNombre { get; init; }
    public string?   ProximoPaso          { get; init; }
    // Contadores de los tabs
    public int       CantidadPropuestas   { get; init; }
    public int       CantidadOc           { get; init; }
    public int       CantidadVb           { get; init; }
    public int       CantidadOs           { get; init; }
    // Acciones rápidas
    public bool      PuedeReasignar       { get; init; }
    public bool      PuedeExportar        { get; init; }
}

/// <summary>Etapa del stepper: completado, en_curso, bloqueado, pendiente, cancelado o no_aplica.</summary>
public record EtapaExpedienteDto(
    int Orden, string Etapa, string Nombre, string Estado, string? Area, string? AreaNombre, DateTime? Inicio, DateTime? Fin,
    long? IdResponsable, string? Responsable, int? SlaHoras, decimal? HorasReales, bool? CumpleSla);

/// <summary>Responsable actual por rol: comercial, operaciones, ssoma o tecnico (sin usuario = pendiente de asignar).</summary>
public record ResponsableActualDto(string Rol, long? IdUsuario, string? Nombre, string? Cargo);

/// <summary>Nodo del árbol de entidades (RQ → propuestas → OC / OS / OM). Activa = sigue viva y se puede reasignar.</summary>
public record EntidadExpedienteDto
{
    public string    Clave          { get; init; } = "";
    public string?   ClavePadre     { get; init; }
    public int       Nivel          { get; init; }
    /// <summary>requerimiento, propuesta, orden_compra, orden_servicio u orden_metrologia.</summary>
    public string    EntidadTipo    { get; init; } = "";
    public long      IdEntidad      { get; init; }
    public string?   Codigo         { get; init; }
    public int?      Version        { get; init; }
    public string?   Estado         { get; init; }
    public decimal?  Monto          { get; init; }
    public string?   SimboloMoneda  { get; init; }
    public long?     IdResponsable  { get; init; }
    public string?   Responsable    { get; init; }
    public DateTime? Fecha          { get; init; }
    public DateTime? FechaEnvio     { get; init; }
    public DateTime? FechaCierre    { get; init; }
    public string?   Detalle        { get; init; }
    public bool      Activa         { get; init; }
    public bool      EsPropuestaActiva { get; init; }
}

/// <summary>Bloqueo, excepción o alerta de SLA activa (resumen de la ficha). Clase: bloqueo, excepcion o alerta.</summary>
public record AlertaExpedienteDto(
    string    Clave,
    string    Clase,
    string?   Tipo,
    string?   TipoNombre,
    string?   Etapa,
    string?   EtapaNombre,
    string?   EntidadTipo,
    long?     IdEntidad,
    string?   Entidad,
    string?   Motivo,
    string?   Impacto,
    bool      Critico,
    DateTime? Fecha,
    string?   Origen,
    long?     IdUsuario,
    string?   Usuario);

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
    bool      Urgente,
    string?   Origen)
{
    /// <summary>Cargo del usuario, ej. "(Jefe Comercial)" junto al nombre en Auditoría.</summary>
    public string? CargoUsuario { get; init; }
}

public record DetalleExpedienteDto(
    CabeceraExpedienteDto                 Cabecera,
    IReadOnlyList<EtapaExpedienteDto>     Etapas,
    IReadOnlyList<ResponsableActualDto>   Responsables,
    IReadOnlyList<EntidadExpedienteDto>   Entidades,
    IReadOnlyList<AlertaExpedienteDto>    Alertas,
    IReadOnlyList<EventoExpedienteDto>    ActividadReciente);

// ── HU-30 Tabs (carga perezosa) ──────────────────────────────────────────────

/// <summary>Evento genérico de un timeline de tab (RQ, propuesta, seguimiento, OC).</summary>
public record EventoTabDto(DateTime? Fecha, string? Tipo, string? Titulo, string? Descripcion, long? IdUsuario, string? Usuario);

/// <summary>Archivo que se ve o descarga con GET /api/expedientes/{id}/documentos/{clave}.</summary>
public record ArchivoTabDto(string Clave, string? NombreArchivo, string? Tipo, long? TamanoBytes, DateTime? Fecha, string? Usuario);

// Tab RQ
public record DatosRqExpedienteDto
{
    public long      IdRequerimiento   { get; init; }
    public string    Numero            { get; init; } = "";
    public string?   Estado            { get; init; }
    public string?   EstadoNombre      { get; init; }
    public string?   Origen            { get; init; }
    public string?   GradoNecesidad    { get; init; }
    public string?   AreaServicio      { get; init; }
    public string?   Descripcion       { get; init; }
    public DateTime? FechaRequerida    { get; init; }
    public DateTime? FechaRegistro     { get; init; }
    public DateTime? FechaCierre       { get; init; }
    public bool      RequiereVisita    { get; init; }
    public bool      EsInacal          { get; init; }
    public long?     IdResponsable     { get; init; }
    public string?   Responsable       { get; init; }
    public string?   CargoResponsable  { get; init; }
    public long?     IdCliente         { get; init; }
    public string?   RazonSocial       { get; init; }
    public string?   Ruc               { get; init; }
    public string?   ContactoNombre    { get; init; }
    public string?   ContactoCargo     { get; init; }
    public string?   ContactoArea      { get; init; }
    public string?   ContactoCorreo    { get; init; }
    public string?   ContactoTelefono  { get; init; }
    public string?   SedeNombre        { get; init; }
    public string?   SedeUbicacion     { get; init; }
    public string?   SedeDireccion     { get; init; }
}

public record PropuestaGeneradaDto(
    long IdPropuesta, string Numero, int Version, string Estado, decimal? Total, string? SimboloMoneda, long? IdResponsable,
    string? Responsable, DateTime? FechaCreacion, DateTime? FechaEnvio, DateTime? FechaAceptacion, DateTime? FechaRechazo,
    string? MotivoRechazo);

public record TabRqExpedienteDto(
    DatosRqExpedienteDto Datos, IReadOnlyList<ArchivoTabDto> Adjuntos, IReadOnlyList<EventoTabDto> Timeline,
    IReadOnlyList<PropuestaGeneradaDto> Propuestas);

// Tab Propuestas
public record VersionPropuestaExpedienteDto(
    long IdPropuesta, string Numero, int Version, string Estado, decimal? Total, string? SimboloMoneda, DateTime? FechaCreacion,
    bool EsUltima, bool EsActiva, bool Seleccionada);

public record DetallePropuestaExpedienteDto
{
    public long      IdPropuesta        { get; init; }
    public string    Numero             { get; init; } = "";
    public int       Version            { get; init; }
    public string    Estado             { get; init; } = "";
    public string?   TipoPropuesta      { get; init; }
    public string?   Referencia         { get; init; }
    public long?     IdResponsable      { get; init; }
    public string?   Responsable        { get; init; }
    public string?   Moneda             { get; init; }
    public string?   SimboloMoneda      { get; init; }
    public decimal?  Subtotal           { get; init; }
    public decimal?  DescuentoMonto     { get; init; }
    public decimal?  DescuentoPct       { get; init; }
    public bool      AplicaIgv          { get; init; }
    public decimal?  IgvPct             { get; init; }
    public decimal?  IgvMonto           { get; init; }
    public decimal?  Total              { get; init; }
    public string?   CondicionPago      { get; init; }
    public int?      PlazoEntregaDias   { get; init; }
    public int?      VigenciaDias       { get; init; }
    public DateTime? FechaExpiracion    { get; init; }
    public DateTime? FechaCreacion      { get; init; }
    public DateTime? FechaEnvio         { get; init; }
    public DateTime? FechaAceptacion    { get; init; }
    public string?   DescripcionCambios { get; init; }
    public string?   MotivoNuevaVersion { get; init; }
    /// <summary>JSON de secciones incluidas, tal cual lo guarda el módulo de propuestas.</summary>
    public string?   SeccionesActivas   { get; init; }
    public string    ClavePdf           { get; init; } = "";
    public string?   NombrePdf          { get; init; }
    public string?   NumeroRq           { get; init; }
    // Contacto y Cliente de la propuesta
    public long?     IdContacto         { get; init; }
    public string?   Contacto           { get; init; }
    public string?   CargoContacto      { get; init; }
    public string?   CorreoContacto     { get; init; }
    public string?   TelefonoContacto   { get; init; }
    public long?     IdSede             { get; init; }
    public string?   Sede               { get; init; }
    /// <summary>Contacto y sede de la propuesta agrupados (sección "Contacto y Cliente").</summary>
    public ContactoClienteExpedienteDto? ContactoCliente { get; init; }
    /// <summary>Suministros del cliente incluidos en la propuesta (viñetas de la sección).</summary>
    public int       Suministros        { get; init; }
}

public record ContactoClienteExpedienteDto(
    long? IdContacto, string? Nombre, string? Cargo, string? Area, string? Correo, string? Telefono,
    long? IdSede, string? SedeNombre, string? SedeUbicacion, string? SedeDireccion);

/// <summary>OC vinculada a la versión de la propuesta ("Órdenes de compra vinculadas desde esta propuesta").</summary>
public record OcPropuestaExpedienteDto(
    long IdOc, string NumeroOc, string Estado, bool EsAutogenerada, bool Reemplazada, int? IdMonedaOc, string? SimboloMonedaOc,
    decimal MontoTotal, decimal MontoAsignado, decimal? MontoCubierto, string? EstadoValidacion, string? ResultadoIa,
    int? Criticas, int? Advertencias, long? IdResponsable, string? Responsable, DateTime? FechaEmision,
    DateTime? FechaRecepcion, DateTime? FechaRegistro)
{
    /// <summary>Igual a SimboloMonedaOc.</summary>
    public string? SimboloMoneda => SimboloMonedaOc;
    /// <summary>Texto corto de la validación de esta vinculación: "OK", "Validación parcial", "Observada", "Pendiente"…</summary>
    public string? Validacion => EstadoValidacion switch
    {
        "validada"  => "OK",
        "observada" => Criticas is > 0 ? "Observada (crítica)" : "Validación parcial",
        "pendiente" => "Pendiente",
        null        => null,
        _           => EstadoValidacion,
    };
}

public record FormaPagoExpedienteDto(decimal? Porcentaje, string? Condicion, int Orden);

public record ItemPropuestaExpedienteDto(
    long IdItem, string Seccion, string? Descripcion, decimal? Cantidad, decimal? PrecioUnitario, decimal? Descuento,
    decimal? Subtotal, string? Alcance, string? PuntosCalibracion, decimal? Frecuencia);

public record EquipoPropuestaExpedienteDto(
    long? IdEquipo, string? Tipo, string? Subtipo, string? Marca, string? Modelo, string? NumeroSerie, string? CodigoCliente,
    string? CodigoTw, string? LocalSede);

public record VistoBuenoVersionDto(
    long IdVb, string Estado, long? IdAprobador, string? Aprobador, string? CargoAprobador, DateTime? FechaSolicitud,
    DateTime? FechaRespuesta, long? IdResueltoPor, string? ResueltoPor, string? Comentario, string? MotivoRechazo);

public record TabPropuestasExpedienteDto(
    IReadOnlyList<VersionPropuestaExpedienteDto>           Versiones,
    DetallePropuestaExpedienteDto?               Detalle,
    IReadOnlyList<FormaPagoExpedienteDto>        FormasPago,
    IReadOnlyList<ItemPropuestaExpedienteDto>    Items,
    IReadOnlyList<EquipoPropuestaExpedienteDto>  Equipos,
    IReadOnlyList<VistoBuenoVersionDto>          VistosBuenos,
    IReadOnlyList<EventoTabDto>                  Timeline)
{
    public IReadOnlyList<OcPropuestaExpedienteDto> OrdenesCompra { get; init; } = [];
    /// <summary>Órdenes de servicio generadas desde la propuesta (con la OC que las cubre: idOc, numeroOc).</summary>
    public IReadOnlyList<OsVinculadaOcExpedienteDto> OrdenesServicio { get; init; } = [];
}

// Tab Visto Bueno
public record PropuestaPillDto(string Numero, int Version, bool Seleccionada);

public record EstadoVistoBuenoDto
{
    public string?   Numero               { get; init; }
    public long?     IdPropuestaRevision  { get; init; }
    public int?      VersionRevision      { get; init; }
    public string?   EstadoPropuesta      { get; init; }
    /// <summary>sin_solicitud, pendiente, aprobado, rechazado, devuelto…</summary>
    public string?   EstadoVb             { get; init; }
    /// <summary>VB vigente (para "Ir al Módulo VB").</summary>
    public long?     IdVb                 { get; init; }
    public long?     IdAprobador          { get; init; }
    public string?   Aprobador            { get; init; }
    public string?   CargoAprobador       { get; init; }
    public string?   AreaAprobador        { get; init; }
    public string?   CorreoAprobador      { get; init; }
    public string?   TelefonoAprobador    { get; init; }
    /// <summary>Estado del usuario aprobador (activo, inactivo…): badge "Activo · En funciones".</summary>
    public string?   EstadoAprobador      { get; init; }
    /// <summary>true = aprobador por defecto (jefe directo o su suplente); false = reasignado.</summary>
    public bool?     AprobadorPorDefecto  { get; init; }
    public long?     IdComercial          { get; init; }
    public string?   Comercial            { get; init; }
    /// <summary>El aprobador es el jefe directo del comercial ("Es el supervisor directo de …").</summary>
    public bool?     EsJefeDirectoComercial { get; init; }
    public long?     IdPropuestaAprobada  { get; init; }
    public int?      VersionAprobada      { get; init; }
    public decimal?  MontoAprobado        { get; init; }
    public string?   SimboloMoneda        { get; init; }
    public DateTime? FechaAprobacion      { get; init; }
    public DateTime? FechaSolicitud       { get; init; }
    public int?      SlaHoras             { get; init; }
    public decimal?  HorasHabiles         { get; init; }
    public bool?     DentroSla            { get; init; }
    public string?   Comentario           { get; init; }
}

public record DecisionVbExpedienteDto(
    long IdVb, long IdPropuesta, int Version, string Estado, long? IdAprobador, string? Aprobador, string? CargoAprobador,
    long? IdRevisor, string? Revisor, string? CargoRevisor, DateTime? FechaSolicitud, DateTime? FechaRespuesta,
    string? Comentario, string? MotivoRechazo, decimal? HorasRevision, int? SlaHoras);

public record ReasignacionAprobadorDto(
    long IdVb, int Version, DateTime? Fecha, long? IdAnterior, string? AprobadorAnterior, long? IdNuevo, string? AprobadorNuevo,
    string? Motivo, string? Comentario, string? EjecutadoPor);

public record MetricasVistoBuenoDto(
    int VersionesTotales, int VersionesDevueltas, decimal? DiasTotales, decimal? DiasPromedioRevision, int DecisionesEnSla, int Decisiones);

public record TabVistoBuenoExpedienteDto(
    IReadOnlyList<PropuestaPillDto>          Propuestas,
    EstadoVistoBuenoDto?                     Estado,
    IReadOnlyList<DecisionVbExpedienteDto>     Decisiones,
    IReadOnlyList<ReasignacionAprobadorDto>  Reasignaciones,
    MetricasVistoBuenoDto?                   Metricas);

// Tab Seguimiento
public record EstadoSeguimientoExpedienteDto
{
    public string?   Numero              { get; init; }
    public long?     IdPropuesta         { get; init; }
    public int?      Version             { get; init; }
    public string?   EstadoPropuesta     { get; init; }
    /// <summary>sin_seguimiento, activo, cerrado_aceptacion o cerrado_rechazo.</summary>
    public string?   EstadoSeguimiento   { get; init; }
    public DateTime? FechaEnvio          { get; init; }
    public DateTime? FechaCierre         { get; init; }
    public decimal?  DiasSeguimiento     { get; init; }
    public long?     IdComercial         { get; init; }
    public string?   Comercial           { get; init; }
    public string?   CargoComercial      { get; init; }
    public string?   CorreoComercial     { get; init; }
    public string?   TelefonoComercial   { get; init; }
    public string?   AreaComercial       { get; init; }
    public string?   Contacto            { get; init; }
    public string?   CargoContacto       { get; init; }
    public string?   CorreoContacto      { get; init; }
    public DateTime? UltimaInteraccion   { get; init; }
    public int       TotalInteracciones  { get; init; }
    public int?      SlaHoras            { get; init; }
    public bool?     SlaCumplido         { get; init; }
}

public record InteraccionSeguimientoDto(
    DateTime? Fecha, string Tipo, string? Titulo, string? Canal, string? Resultado, string? Asunto, string? Detalle,
    int? DuracionMinutos, DateTime? ProximaAccionFecha, string? ProximaAccion, int? Version, long? IdUsuario, string? Usuario,
    IReadOnlyList<ArchivoTabDto> Adjuntos)
{
    /// <summary>Contacto de la interacción, "Para" del correo o contacto de la propuesta en el envío.</summary>
    public string? Destinatario   { get; init; }
    /// <summary>Resumen del cuerpo del correo (texto, 300 caracteres).</summary>
    public string? ResumenCuerpo  { get; init; }
    public string? TipoAceptacion { get; init; }
}

public record ResultadoSeguimientoDto(
    string Resultado, DateTime? FechaCierre, long? IdRegistradoPor, string? RegistradoPor, string? TipoEvidencia,
    string? MotivoRechazo, string? Canal, string? Comentario, decimal? MontoComprometido, string? SimboloMoneda,
    decimal? DiasHastaCierre, bool PermiteReactivacion);

public record TabSeguimientoExpedienteDto(
    IReadOnlyList<PropuestaPillDto>           Propuestas,
    EstadoSeguimientoExpedienteDto?           Estado,
    IReadOnlyList<InteraccionSeguimientoDto>  Interacciones,
    ResultadoSeguimientoDto?                  Resultado,
    IReadOnlyList<ArchivoTabDto>              Evidencias);

// Tab OC
public record OcPillDto(long IdOc, string NumeroOc, string Estado, bool EsAutogenerada, bool Vigente, long? IdPropuesta,
                        string? Propuesta, bool Seleccionada);

public record DatosOcExpedienteDto
{
    public long      IdOc               { get; init; }
    public string    NumeroOc           { get; init; } = "";
    public string    Estado             { get; init; } = "";
    public bool      EsAutogenerada     { get; init; }
    public string?   Referencia         { get; init; }
    public DateTime? FechaEmision       { get; init; }
    public DateTime? FechaRecepcion     { get; init; }
    public DateTime? FechaRegistro      { get; init; }
    public DateTime? VigenciaHasta      { get; init; }
    public string?   Moneda             { get; init; }
    public string?   SimboloMoneda      { get; init; }
    public decimal?  MontoTotal         { get; init; }
    public decimal?  MontoAsignado      { get; init; }
    public decimal?  Saldo              { get; init; }
    public string?   FormaPago          { get; init; }
    public bool      IgvIncluido        { get; init; }
    public decimal?  IgvPct             { get; init; }
    public bool      FacturaIgualOc     { get; init; }
    public string?   Observaciones      { get; init; }
    public string?   ClavePdf           { get; init; }
    public string?   NombreArchivoPdf   { get; init; }
    public long?     TamanoPdfBytes     { get; init; }
    public string?   ReemplazadaPor     { get; init; }
    public DateTime? FechaReemplazo     { get; init; }
    public DateTime? FechaAnulacion     { get; init; }
    public string?   MotivoAnulacion    { get; init; }
    public string?   JustificacionAnulacion { get; init; }
    public long?     IdResponsable      { get; init; }
    public string?   Responsable        { get; init; }
    public long?     IdRegistradoPor    { get; init; }
    public string?   RegistradoPor      { get; init; }
}

/// <summary>Validación de una sub-aplicación (OC ↔ propuesta). Confianza en escala 0–100.</summary>
public record ValidacionOcExpedienteDto(
    long IdPropuesta, string Propuesta, string? EstadoPropuesta, bool DeEsteExpediente, decimal? MontoAsignado,
    decimal? PorcentajeOc, string? EstadoValidacion, string? TipoObservacion, string? ResultadoIa, DateTime? FechaDecision,
    int? Corrida, int? Coincidencias, int? Advertencias, int? Criticas, int? TotalCampos, decimal? Confianza, string? Motor,
    string? Dictamen, string? Sugerencia, DateTime? FechaValidacion);

public record CampoValidacionOcDto(int? Orden, string? Campo, string? Etiqueta, string? ValorOc, string? ValorPropuesta,
                                   string? Severidad, string? Mensaje);

public record EventoOcExpedienteDto(
    DateTime? Fecha, string? Accion, string? Titulo, string? Descripcion, string? EstadoAnterior, string? EstadoNuevo,
    long? IdUsuario, string? Usuario, bool AutomaticoIa);

public record TabOrdenesCompraExpedienteDto(
    IReadOnlyList<OcPillDto>                   OrdenesCompra,
    DatosOcExpedienteDto?                      Datos,
    IReadOnlyList<ValidacionOcExpedienteDto>   Validaciones,
    IReadOnlyList<CampoValidacionOcDto>        Campos,
    IReadOnlyList<EventoOcExpedienteDto>       Timeline)
{
    /// <summary>Órdenes de servicio cubiertas por la OC elegida (el detalle va en el tab Propuestas).</summary>
    public IReadOnlyList<OsVinculadaOcExpedienteDto> OrdenesServicio { get; init; } = [];
    /// <summary>"N OS cubiertas por esta OC".</summary>
    public int OrdenesServicioCubiertas => OrdenesServicio.Count;
}

public record OsVinculadaOcExpedienteDto(
    long IdOs, string Numero, string Estado, decimal? CostoEstimado, DateTime? FechaEjecucion, string? HoraInicio,
    long? IdTecnico, string? Tecnico, long? IdResponsableComercial, string? ResponsableComercial, string? ConfirmacionCliente,
    long IdExpediente, string? NumeroExpediente)
{
    /// <summary>Igual a FechaEjecucion.</summary>
    public DateTime? FechaProgramada  => FechaEjecucion;
    /// <summary>Igual a Tecnico.</summary>
    public string?   TecnicoPrincipal => Tecnico;
    /// <summary>Demás personal asignado a la OS (sin el técnico principal).</summary>
    public string?   Ejecutor         { get; init; }
    /// <summary>Lo que la OC asignó a la propuesta de esta OS (moneda de la OC).</summary>
    public decimal?  MontoPropuestaOc { get; init; }
    public string?   SimboloMoneda    { get; init; }
    /// <summary>OC que cubre la OS (en el tab Propuestas).</summary>
    public long?     IdOc             { get; init; }
    public string?   NumeroOc         { get; init; }
}

// Tab OS
public record OsPillDto(long IdOs, string Numero, string Estado, DateTime? FechaEjecucion, bool Seleccionada);

public record DatosOsExpedienteDto
{
    public long      IdOs                   { get; init; }
    public string    Numero                 { get; init; } = "";
    public string    Estado                 { get; init; } = "";
    public DateTime? FechaCreacion          { get; init; }
    public DateTime? FechaEjecucion         { get; init; }
    public string?   HoraInicio             { get; init; }
    public string?   HoraFinEstimada        { get; init; }
    public string?   HoraLlegadaReal        { get; init; }
    public string?   HoraFinReal            { get; init; }
    public decimal?  CostoTotalEstimado     { get; init; }
    public string?   TipoServicio           { get; init; }
    public string?   Sede                   { get; init; }
    public string?   SedeDireccion          { get; init; }
    public long?     IdTecnicoPrincipal     { get; init; }
    public string?   TecnicoPrincipal       { get; init; }
    public long?     IdResponsableComercial { get; init; }
    public string?   ResponsableComercial   { get; init; }
    public bool      ConfirmacionCliente    { get; init; }
    public DateTime? FechaConfirmacion      { get; init; }
    public string?   CanalConfirmacion      { get; init; }
    public string?   ContactoConfirma       { get; init; }
    public string?   NotasOperativas        { get; init; }
    public string?   GeneradoPor            { get; init; }
}

public record PersonalOsDto(long IdUsuario, string? Nombre, string? Cargo, string? RolEnServicio, string? EstadoSsoma);

public record EquipoOsDto(long IdEquipo, string? CodigoTw, string? CodigoCliente, string? Marca, string? Modelo,
                          string? NumeroSerie, string? Ubicacion, string? TipoIntervencion, bool IngresadoEnCampo);

public record GastoOsDto(long IdGasto, string? Tipo, string? Concepto, decimal? Monto, string? SimboloMoneda, string? Descripcion,
                         string? Estado, DateTime? FechaSolicitud, string? Usuario);

public record OrdenMetrologiaExpedienteDto(long IdOm, string Numero, string? Estado, DateTime? FechaCalibracion,
                                           string? NumeroCertificado, DateTime? FechaEmisionCertificado, string? Metrologo);

public record TabOrdenServicioExpedienteDto(
    IReadOnlyList<OsPillDto>                     OrdenesServicio,
    DatosOsExpedienteDto?                        Datos,
    IReadOnlyList<PersonalOsDto>                 Personal,
    IReadOnlyList<EquipoOsDto>                   Equipos,
    IReadOnlyList<GastoOsDto>                    Gastos,
    IReadOnlyList<OrdenMetrologiaExpedienteDto>  OrdenesMetrologia);

// Tab Programación
public record CalendarioOsDto(long IdOs, string Numero, string Estado, DateTime? FechaEjecucion, string? HoraInicio,
                              string? HoraFinEstimada, long? IdTecnicoPrincipal, string? TecnicoPrincipal, string? Sede,
                              bool ConfirmacionCliente, DateTime? FechaConfirmacion);

public record RecursoReservadoDto(string? Os, string TipoRecurso, string? Recurso, string? Detalle, string? Estado);

public record BacklogProgramacionDto(long IdBacklog, string? Os, string? Om, string? Prioridad, string? TecnicoSugerido,
                                     DateTime? FechaLimite, string? Estado, string? Notas, DateTime? Creado, DateTime? Modificado);

public record PresalidaDto(string? Os, string? Descripcion, bool Confirmado, DateTime? ConfirmadoEn, string? ConfirmadoPor);

public record TabProgramacionExpedienteDto(
    IReadOnlyList<CalendarioOsDto>        Calendario,
    IReadOnlyList<RecursoReservadoDto>    Recursos,
    IReadOnlyList<BacklogProgramacionDto> Backlog,
    IReadOnlyList<PresalidaDto>           Presalida);

// Tab SSOMA
public record ResumenSsomaDto(int Personal, int Habilitados, int Pendientes, int Bloqueados, int Observados, int Vencidos,
                              string EstadoGlobal);

public record ChecklistSsomaDto(string? Os, long IdUsuario, string? Tecnico, string? RolEnServicio, string? EstadoSsoma,
                                int? IdRequisito, string? Requisito, string? EstadoDocumento, DateTime? FechaVencimiento);

public record DocumentoSsomaDto(string Clave, string? Os, string? Tecnico, string? Tipo, string? NombreArchivo, string? Estado,
                                int Version, DateTime? FechaCarga, DateTime? FechaVencimiento, string? MotivoObservacion,
                                string? AprobadoPor);

public record RequisitoSsomaExpedienteDto(int IdRequisito, string? Requisito, bool EsObligatorio, bool BloqueaServicio, string? Sede);

public record TabSsomaExpedienteDto(
    ResumenSsomaDto?                          Resumen,
    IReadOnlyList<ChecklistSsomaDto>          Checklist,
    IReadOnlyList<DocumentoSsomaDto>          Documentos,
    IReadOnlyList<RequisitoSsomaExpedienteDto>   RequisitosCliente);

// Tab Ejecución
public record ResumenEjecucionOsDto(long IdOs, string Numero, string Estado, DateTime? FechaEjecucion, string? HoraInicio,
                                    string? HoraLlegadaReal, string? HoraFinReal, decimal? Latitud, decimal? Longitud,
                                    string? TecnicoPrincipal);

public record EventoCampoDto(long IdEvento, string? Os, DateTime? Fecha, int IdTipoEvento, string? TipoEvento, decimal? Latitud,
                             decimal? Longitud, string? Notas, bool Sincronizado, string? Usuario);

public record EvidenciaEjecucionDto(string Clave, string? Os, string? TipoEvidencia, string? NombreArchivo, DateTime? Fecha,
                                    decimal? Latitud, decimal? Longitud, string? ValidacionIa, bool OverrideAprobado,
                                    string? Usuario);

public record IncidenciaExpedienteDto(long IdIncidencia, string? Os, string? Tipo, string? Descripcion, string? NivelAlerta,
                                      string? Estado, DateTime? FechaRegistro, string? Usuario);

public record DemoraExpedienteDto(long IdDemora, string? Os, string? Motivo, string? Descripcion, int? DuracionMinutos,
                                  DateTime? FechaRegistro, string? Usuario);

public record TabEjecucionExpedienteDto(
    IReadOnlyList<ResumenEjecucionOsDto>   OrdenesServicio,
    IReadOnlyList<EventoCampoDto>          EventosCampo,
    IReadOnlyList<EvidenciaEjecucionDto>   Evidencias,
    IReadOnlyList<IncidenciaExpedienteDto> Incidencias,
    IReadOnlyList<DemoraExpedienteDto>     Demoras);

// Tab Cierre
public record ResumenCierreDto(string EstadoCierre, DateTime? FechaCierre, int Informes, int InformesAprobados, int Conformes,
                               int Observadas);

public record InformeTecnicoExpedienteDto(long IdInforme, string Numero, string? Os, int Version, string Estado,
                                          string? DiagnosticoPrincipal, string? Hallazgos, DateTime? FechaCreacion,
                                          DateTime? FechaEnvioCliente, string? ClavePdf, string? Tecnico, string? Revisor);

public record ConformidadExpedienteDto(long IdConformidad, string? Informe, string? Os, string? Tipo, string? Estado,
                                       string? Observaciones, DateTime? RegistradoEn, string? Contacto, string? CargoContacto);

public record CertificadoExpedienteDto(string? Clave, string Numero, string? NumeroCertificado, DateTime? FechaEmision, string? Estado);

public record TabCierreExpedienteDto(
    ResumenCierreDto?                          Resumen,
    IReadOnlyList<InformeTecnicoExpedienteDto> Informes,
    IReadOnlyList<ConformidadExpedienteDto>    Conformidades,
    IReadOnlyList<CertificadoExpedienteDto>    Certificados);

// ── HU-31 Repositorio de documentos ──────────────────────────────────────────

public record FiltrosDocumentosExpedienteDto
{
    /// <summary>todos (defecto), comerciales, operativos, ssoma o tecnicos.</summary>
    public string?   Categoria { get; init; }
    /// <summary>Nombre, tipo o módulo origen.</summary>
    public string?   Busqueda  { get; init; }
    public DateTime? Desde     { get; init; }
    public DateTime? Hasta     { get; init; }
    public string?   Estado    { get; init; }
    /// <summary>PDF, XLSX, DOCX, EML, JPG, PNG u OTRO.</summary>
    public string?   Formato   { get; init; }
    /// <summary>desc (defecto, más recientes primero) o asc.</summary>
    public string?   Orden     { get; init; }
}

public record PestanaDocumentosDto(string Codigo, string Nombre, int Cantidad);

public record DocumentoExpedienteDto
{
    public string    Clave           { get; init; } = "";
    public string    Nombre          { get; init; } = "";
    public string?   NombreArchivo   { get; init; }
    public string?   Tipo            { get; init; }
    public string    Categoria       { get; init; } = "";
    /// <summary>Módulo + etapa consolidados, ej. "Propuesta — VB".</summary>
    public string?   Origen          { get; init; }
    public string?   Modulo          { get; init; }
    public string?   EtapaOrigen     { get; init; }
    public string?   Etapa           { get; init; }
    public string?   EtapaNombre     { get; init; }
    /// <summary>Rol del documento (chip): generada, comunicacion, adjunto_cliente, documento_origen, habilitacion,
    /// induccion, certificado, evidencia u otro.</summary>
    public string?   RolDocumento    { get; init; }
    public int       Version         { get; init; }
    public string    Estado          { get; init; } = "";
    public DateTime? Fecha           { get; init; }
    public long?     IdUsuario       { get; init; }
    public string?   Usuario         { get; init; }
    public string?   CargoUsuario    { get; init; }
    public string?   AreaUsuario     { get; init; }
    public long?     TamanoBytes     { get; init; }
    public string?   TipoContenido   { get; init; }
    public string?   Formato         { get; init; }
    public string?   Descripcion     { get; init; }
    public string?   Visibilidad     { get; init; }
    public bool      EsInterno       { get; init; }
    public bool      Descargable     { get; init; }
    public bool      Previsualizable { get; init; }
}

public record DocumentosExpedienteDto(
    long    IdExpediente,
    string  Numero,
    string? RazonSocial,
    string? Ruc,
    int     TotalDocumentos,
    IReadOnlyList<PestanaDocumentosDto>    Pestanas,
    IReadOnlyList<DocumentoExpedienteDto>  Documentos,
    IReadOnlyList<OpcionExpedienteDto>     Estados,
    IReadOnlyList<OpcionExpedienteDto>     Formatos);

/// <summary>
/// Ubicación de un archivo del expediente: ruta en el almacenamiento, propuesta cuyo PDF se genera o correo de seguimiento
/// que se arma como .eml.
/// </summary>
public record UbicacionArchivoExpedienteDto(
    string? Ruta, string NombreArchivo, string? TipoContenido, long? IdPropuesta, CorreoSeguimientoArchivoDto? Correo);

public record CorreoSeguimientoArchivoDto(
    long IdCorreo, string? Asunto, string? Para, string? Cc, string? CuerpoHtml, DateTime? Fecha, string? Remitente);

public record ArchivoExportacionExpedienteDto(
    string Clave, string Categoria, string Carpeta, string NombreArchivo, int Version, string Estado, string? Ruta,
    long? IdPropuesta, CorreoSeguimientoArchivoDto? Correo);

// ── HU-32 Historial de auditoría ─────────────────────────────────────────────

public record FiltrosHistorialExpedienteDto
{
    /// <summary>Texto en comentarios, usuario o entidad.</summary>
    public string?   Busqueda   { get; init; }
    public long?     IdUsuario  { get; init; }
    public string?   Etapa      { get; init; }
    /// <summary>Solo para el tab Timeline.</summary>
    public string?   TipoEvento { get; init; }
    public DateTime? Desde      { get; init; }
    public DateTime? Hasta      { get; init; }
}

public record UsuarioFiltroDto(long IdUsuario, string Nombre);

public record TabAuditoriaDto(string Codigo, string Nombre, int Cantidad);

public record ReasignacionHistorialDto(
    long? IdReasignacion, DateTime? Fecha, string? Modo, string? Alcance, string? Entidades, long? IdDe, string? De, long? IdA,
    string? A, string? Motivo, string? Comentario, string? GestionSla, string? DecisionSla, long? IdEjecutadoPor,
    string? EjecutadoPor, string? Etapa);

public record BloqueoHistorialDto(
    string Clave, DateTime? Fecha, string Clase, string? Tipo, string? TipoNombre, string? Etapa, string? EtapaNombre,
    string? EntidadTipo, string? Entidad, string? Motivo, string? Impacto, DateTime? FechaResolucion, string? Resolucion,
    bool Activo, decimal? DuracionHoras, long? IdUsuario, string? Usuario, string? Origen);

/// <summary>Alerta de SLA: advertencia (50 % del SLA), riesgo (ventana de alerta) o vencido.</summary>
public record AlertaSlaHistorialDto(
    DateTime? Fecha, string Etapa, string? EtapaNombre, string Nivel, int? SlaHoras, decimal? HorasReales, decimal? DesvioHoras,
    long? IdResponsable, string? Responsable, string? AccionTomada);

public record HistorialExpedienteDto(
    long    IdExpediente,
    string  Numero,
    string? RazonSocial,
    string? Ruc,
    long?   IdResponsable,
    string? Responsable,
    IReadOnlyList<TabAuditoriaDto>          Tabs,
    IReadOnlyList<EventoExpedienteDto>      Timeline,
    IReadOnlyList<ReasignacionHistorialDto> Reasignaciones,
    IReadOnlyList<BloqueoHistorialDto>      Bloqueos,
    IReadOnlyList<AlertaSlaHistorialDto>    AlertasSla,
    IReadOnlyList<OpcionExpedienteDto>      TiposEvento,
    IReadOnlyList<UsuarioFiltroDto>         Usuarios,
    IReadOnlyList<OpcionExpedienteDto>      Etapas);

// ── HU-33 Reasignación ───────────────────────────────────────────────────────

public record DatosReasignacionExpedienteDto(
    long IdExpediente, string Numero, string? RazonSocial, string? Ruc, string Etapa, string? EtapaNombre, long? IdResponsable,
    string? Responsable, string? CargoResponsable, string? AreaResponsable, SlaExpedienteDto Sla, string NotaImpacto);

public record PreparacionReasignacionExpedienteDto(
    DatosReasignacionExpedienteDto        Datos,
    IReadOnlyList<EntidadExpedienteDto>   Entidades,
    IReadOnlyList<OpcionIdExpedienteDto>  Motivos,
    IReadOnlyList<OpcionExpedienteDto>    GestionesSla);

public record ResumenCarteraComercialDto(
    long IdResponsable, string? Responsable, string? CargoResponsable, string? AreaResponsable, int TotalEntidades,
    int Expedientes, int Requerimientos, int Propuestas, int OrdenesCompra, int OrdenesServicio);

public record EntidadCarteraDto(long IdExpediente, string EntidadTipo, long IdEntidad, string? Codigo, string? Estado, string? Detalle);

public record ExpedienteCarteraDto(
    long IdExpediente, string Numero, string? Cliente, string Etapa, string? EtapaNombre, string? SlaEstado,
    int? SlaMinutosRestantes, DateTime? FechaLimite, int Entidades, IReadOnlyList<EntidadCarteraDto> Detalle);

public record CarteraComercialExpedienteDto(ResumenCarteraComercialDto Resumen, IReadOnlyList<ExpedienteCarteraDto> Expedientes);

public record CandidatoResponsableDto(
    long IdUsuario, string Nombre, string? Correo, string? Cargo, string? Area, string? AreaNombre, string? Rol, string? SedeOperativa);

public record ReasignarResponsableExpedienteDto
{
    /// <summary>entidad (Opción A), cascada (Opción B) o global (Opción C).</summary>
    public string?               Modo                 { get; init; }
    /// <summary>Opciones A y B: requerimiento, propuesta, orden_compra u orden_servicio.</summary>
    public string?               EntidadTipo          { get; init; }
    public long?                 IdEntidad            { get; init; }
    /// <summary>Opción B personalizada: claves de las entidades desmarcadas (ej. "oc-12", "os-3"); la raíz no se excluye.</summary>
    public IReadOnlyList<string>? Excluidos           { get; init; }
    /// <summary>Opción C: comercial cuya cartera se reasigna (por defecto el responsable actual del expediente).</summary>
    public long?                 IdResponsableActual  { get; init; }
    public long?                 IdNuevoResponsable   { get; init; }
    public int?                  IdMotivo             { get; init; }
    /// <summary>Obligatorio, mínimo 20 caracteres.</summary>
    public string?               Comentario           { get; init; }
    /// <summary>mantener | reiniciar</summary>
    public string?               GestionSla           { get; init; }
}

public record EntidadReasignadaDto(
    long IdExpediente, string NumeroExpediente, string? Cliente, string EntidadTipo, long IdEntidad, string? Codigo,
    long? IdResponsableAnterior, string? ResponsableAnterior);

public record ResponsableAnteriorDto(long IdUsuario, string Nombre, string? Correo, int Cantidad, string? Codigos);

public record ReasignacionExpedienteDto
{
    public long      IdReasignacion    { get; init; }
    public string    Modo              { get; init; } = "";
    public string?   Alcance           { get; init; }
    public int       TotalEntidades    { get; init; }
    public int       TotalExpedientes  { get; init; }
    public long      IdExpediente      { get; init; }
    public string?   NumeroExpediente  { get; init; }
    public long      IdResponsable     { get; init; }
    public string    Responsable       { get; init; } = "";
    public string?   CorreoResponsable { get; init; }
    public string?   Motivo            { get; init; }
    public string?   Comentario        { get; init; }
    public string?   GestionSla        { get; init; }
    public string?   ReasignadoPor     { get; init; }
    public IReadOnlyList<EntidadReasignadaDto>   Entidades           { get; init; } = [];
    public IReadOnlyList<ResponsableAnteriorDto> ResponsablesAnteriores { get; init; } = [];
    public int       CorreosEnviados   { get; init; }
    public IReadOnlyList<string> CorreosConError { get; init; } = [];
}
