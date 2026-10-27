namespace TW.Intranet.Aplicacion.Dtos;

// ═══════════════════════════════════════════════════════════════════════════
// Módulo Órdenes de Servicio / Metrología (OS / OM), Sprint 4 (HU-40 a HU-44).
// La OS/OM no maneja montos: es el documento operativo que nace de una propuesta aceptada.
// ═══════════════════════════════════════════════════════════════════════════

// ── HU-41 Bandeja ──────────────────────────────────────────────────────────

/// <summary>Filtros de la bandeja (query string).</summary>
public class FiltrosBandejaOrdenesServicioDto
{
    /// <summary>todas (defecto), borrador, emitida, programada, en_ejecucion, finalizada, anulada (la tarjeta pulsada).</summary>
    public string?   Estado        { get; set; }
    /// <summary>todos (defecto), OS u OM.</summary>
    public string?   Tipo          { get; set; }
    public long?     IdCliente     { get; set; }
    /// <summary>Responsable comercial de la orden.</summary>
    public long?     IdResponsable { get; set; }
    /// <summary>Fecha de emisión (los borradores usan su fecha de creación).</summary>
    public DateTime? FechaDesde    { get; set; }
    public DateTime? FechaHasta    { get; set; }
    /// <summary>N° OS/OM, N° de propuesta, cliente o RUC.</summary>
    public string?   Busqueda      { get; set; }
    public int       Pagina        { get; set; } = 1;
    public int       PorPagina     { get; set; } = 10;
}

/// <summary>Tarjetas KPI (con todos los filtros salvo el estado). Cada tarjeta filtra por su estado.</summary>
public record TarjetasOrdenesServicioDto(
    int Total,
    int Borradores,
    int Emitidas,
    /// <summary>Órdenes emitidas desde el lunes de esta semana ("+5 esta semana").</summary>
    int EmitidasSemana,
    int Programadas,
    int EnEjecucion,
    int Finalizadas,
    /// <summary>Finalizadas este mes.</summary>
    int FinalizadasMes,
    int Anuladas);

/// <summary>Fila de la bandeja.</summary>
public record ItemBandejaOrdenServicioDto
{
    public long      IdOs                   { get; init; }
    /// <summary>OS u OM.</summary>
    public string    Tipo                   { get; init; } = "OS";
    public string    Numero                 { get; init; } = "";
    /// <summary>Estado detallado: borrador, emitida, programada, reprogramada, en_ruta, en_ejecucion, pausada, bloqueada, finalizada, anulada.</summary>
    public string    Estado                 { get; init; } = "";
    /// <summary>Grupo de la tarjeta: borrador, emitida, programada, en_ejecucion, finalizada, anulada (color del chip).</summary>
    public string    EstadoGrupo            { get; init; } = "";
    public string    EstadoLabel            { get; init; } = "";
    /// <summary>Fecha de emisión; en un borrador (Emitida = false), su fecha de creación.</summary>
    public DateTime? FechaEmision           { get; init; }
    /// <summary>false = la orden no tiene fecha de emisión registrada (borrador u orden anterior al módulo).</summary>
    public bool      Emitida                { get; init; }
    public long?     IdCliente              { get; init; }
    public string?   RazonSocial            { get; init; }
    public string?   Ruc                    { get; init; }
    public long?     IdPropuesta            { get; init; }
    public string?   NumeroPropuesta        { get; init; }
    public int?      VersionPropuesta       { get; init; }
    public long?     IdRequerimiento        { get; init; }
    public string?   NumeroRequerimiento    { get; init; }
    /// <summary>Para los modales reutilizables de Documentos (HU-31) e Historial de Auditoría (HU-32).</summary>
    public long?     IdExpediente           { get; init; }
    public long?     IdResponsable          { get; init; }
    public string?   Responsable            { get; init; }
    public int       NumeroEquipos          { get; init; }
    public int       NumeroConceptos        { get; init; }
    /// <summary>Hay una solicitud de edición esperando al Jefe Comercial.</summary>
    public bool      SolicitudPendiente     { get; init; }
    public long?     IdSolicitudPendiente   { get; init; }
    /// <summary>El usuario tiene una solicitud de edición aprobada pendiente de ejecutar.</summary>
    public bool      EdicionAprobada        { get; init; }
    // Acciones del menú ⋯ según estado y rol
    public bool      PuedeEditar            { get; init; }
    public bool      PuedeSolicitarEdicion  { get; init; }
    public bool      PuedeResolverSolicitud { get; init; }
    public bool      PuedeAnular            { get; init; }
}

public record BandejaOrdenesServicioDto(
    TarjetasOrdenesServicioDto        Tarjetas,
    List<ItemBandejaOrdenServicioDto> Items,
    int                               Total,
    int                               Pagina,
    int                               PorPagina,
    List<OpcionFiltroDto>             Clientes,
    List<OpcionFiltroDto>             Responsables);

// ── Equipos y conceptos (HU-43) ────────────────────────────────────────────

/// <summary>Equipo / instrumento del cliente en la OS/OM o en el buscador. Columnas condicionales según la clasificación:
/// equipo → d, e, clase; instrumento → escala, puntos de calibración; pesa → valor nominal.</summary>
public record EquipoOrdenServicioDto
{
    public long?   IdOsEquipo         { get; init; }
    public int?    Orden              { get; init; }
    public long    IdEquipo           { get; init; }
    public string  CodigoTw           { get; init; } = "";
    public string  NumSerie           { get; init; } = "";
    public string? CodigoCliente      { get; init; }
    /// <summary>equipo | instrumento | pesa.</summary>
    public string  Clasificacion      { get; init; } = "";
    public string  ClasificacionLabel { get; init; } = "";
    public string  Marca              { get; init; } = "";
    public string  Modelo             { get; init; } = "";
    public string? Alcance            { get; init; }
    public string? Ubicacion          { get; init; }
    public string? Sede               { get; init; }
    /// <summary>d (resolución).</summary>
    public string? DivisionMinima     { get; init; }
    /// <summary>e (escala de verificación).</summary>
    public string? DivisionVerif      { get; init; }
    public string? ClaseExactitud     { get; init; }
    public string? Escala             { get; init; }
    public string? PuntosCalibracion  { get; init; }
    public string? ValorNominal       { get; init; }
    /// <summary>pendiente | en_proceso | ejecutado | observado (Módulo 11).</summary>
    public string? EstadoEjecucion    { get; init; }
    /// <summary>Conceptos que aplican a este equipo (idSuministro).</summary>
    public List<long>   Conceptos     { get; init; } = [];
    /// <summary>Descripciones de los conceptos aplicados (tab Equipos del detalle).</summary>
    public List<string> ConceptosDescripcion { get; init; } = [];
    /// <summary>Precargado desde la propuesta como sugerencia (ficha nueva).</summary>
    public bool    Sugerido           { get; init; }
    /// <summary>Doble registro: OS/OM activa en la que ya está el equipo (null = disponible).</summary>
    public string? OtraOsNumero       { get; init; }
    public string? OtraOsEstado       { get; init; }
    /// <summary>Buscador: el equipo está cotizado en la propuesta de origen.</summary>
    public bool    DeLaPropuesta      { get; init; }
}

/// <summary>Concepto del servicio (suministro de clase Servicio, sin precio).</summary>
public record ConceptoOrdenServicioDto
{
    public long?   IdOsConcepto      { get; init; }
    public long?   IdSuministro      { get; init; }
    public string? Codigo            { get; init; }
    public string  Descripcion       { get; init; } = "";
    public string? Clasificacion     { get; init; }
    public bool    Sugerido          { get; init; }
    /// <summary>Códigos TW de los equipos a los que aplica; vacío = "General" (aplica a toda la orden).</summary>
    public List<string> EquiposAplicados { get; init; } = [];
    public bool    General           => EquiposAplicados.Count == 0;
}

public record ContactoClienteOsDto(long IdContacto, string Nombres, string? Cargo, string? Correo, string? Telefono, bool EsPrincipal);

/// <summary>Los 10 campos de contexto de la propuesta aceptada (sección 2 de la ficha y tab Propuesta Origen).</summary>
public record PropuestaOrigenOsDto
{
    public long      IdPropuesta        { get; init; }
    public string    Numero             { get; init; } = "";
    public int       Version            { get; init; }
    public string?   Estado             { get; init; }
    public string?   TipoServicio       { get; init; }
    public DateTime? FechaAceptacion    { get; init; }
    public string?   Comercial          { get; init; }
    public string?   AprobadorVb        { get; init; }
    /// <summary>Referencial (la OS/OM no maneja montos).</summary>
    public decimal?  MontoTotal         { get; init; }
    public string?   SimboloMoneda      { get; init; }
    public int       EquiposCotizados   { get; init; }
    public int       ConceptosCotizados { get; init; }
    public string?   CondicionPago      { get; init; }
}

/// <summary>Datos para la emisión del certificado (solo OM).</summary>
public record CertificadoOsDto(bool EsTercerizado, bool Editable, string? RazonSocial, string? Ruc, string? Direccion, string? Contacto);

// ── HU-40 Ficha Nueva / Editar ─────────────────────────────────────────────

/// <summary>Ficha de la OS/OM (nueva desde la propuesta o edición).</summary>
public record FichaOrdenServicioDto
{
    /// <summary>nueva | borrador | edicion_aprobada.</summary>
    public string    Modo                 { get; init; } = "nueva";
    public long?     IdOs                 { get; init; }
    /// <summary>En una orden nueva, el número que se le asignará al guardar.</summary>
    public string    Numero               { get; init; } = "";
    /// <summary>OS u OM (lo define el área de la RQ: Metrología → OM).</summary>
    public string    Tipo                 { get; init; } = "OS";
    public string    Estado               { get; init; } = "borrador";
    // Edición autorizada (banner verde)
    public long?     IdSolicitudAprobada  { get; init; }
    public string?   MotivoEdicion        { get; init; }
    public string?   EdicionAprobadaPor   { get; init; }
    public string?   CargoAprobadorEdicion { get; init; }
    public DateTime? FechaAprobacionEdicion { get; init; }
    // 1. Cliente
    public long      IdCliente            { get; init; }
    public string    RazonSocial          { get; init; } = "";
    public string?   Ruc                  { get; init; }
    public long?     IdSede               { get; init; }
    public string?   Sede                 { get; init; }
    public string?   DireccionOperaciones { get; init; }
    public long?     IdContacto           { get; init; }
    public long?     IdResponsable        { get; init; }
    public string?   Responsable          { get; init; }
    public string?   CargoResponsable     { get; init; }
    public List<ContactoClienteOsDto> Contactos { get; init; } = [];
    // 2. Propuesta origen
    public PropuestaOrigenOsDto Propuesta { get; init; } = new();
    // 3. Documento
    public DateTime  FechaEmision         { get; init; }
    public long?     IdRequerimiento      { get; init; }
    public string?   NumeroRq             { get; init; }
    /// <summary>Solo OS (en OM se oculta).</summary>
    public DateTime? FechaProgramadaDesde { get; init; }
    public DateTime? FechaProgramadaHasta { get; init; }
    // 4-5. Conceptos y equipos
    public List<ConceptoOrdenServicioDto> Conceptos { get; init; } = [];
    public List<EquipoOrdenServicioDto>   Equipos   { get; init; } = [];
    // 6. Observaciones
    public string?   Observaciones        { get; init; }
    // 7. Certificado (solo OM)
    public CertificadoOsDto? Certificado  { get; init; }
}

public class EquipoGuardarOsDto
{
    public long       IdEquipo  { get; set; }
    /// <summary>idSuministro de los conceptos que aplican al equipo (vacío = sin concepto asignado).</summary>
    public List<long> Conceptos { get; set; } = [];
}

/// <summary>Resumen de una importación por Excel aplicada en el formulario (HU-44): se registra en la auditoría.</summary>
public class ImportacionAplicadaOsDto
{
    public string? NombreArchivo { get; set; }
    /// <summary>fusionar | reemplazar.</summary>
    public string? Modo          { get; set; }
    public int     Conceptos     { get; set; }
    public int     Equipos       { get; set; }
    public int     Relaciones    { get; set; }
    public int     Advertencias  { get; set; }
}

/// <summary>Guardar borrador / Emitir / Guardar cambios y re-emitir.</summary>
public class GuardarOrdenServicioDto
{
    /// <summary>Obligatorio en una orden nueva.</summary>
    public long?      IdPropuesta          { get; set; }
    public long?      IdContacto           { get; set; }
    public DateTime?  FechaProgramadaDesde { get; set; }
    public DateTime?  FechaProgramadaHasta { get; set; }
    public string?    Observaciones        { get; set; }
    public string?    CertRazonSocial      { get; set; }
    public string?    CertRuc              { get; set; }
    public string?    CertDireccion        { get; set; }
    public string?    CertContacto         { get; set; }
    /// <summary>idSuministro de los conceptos, en orden.</summary>
    public List<long> Conceptos            { get; set; } = [];
    public List<EquipoGuardarOsDto> Equipos { get; set; } = [];
    /// <summary>true = emitir el borrador.</summary>
    public bool       Emitir               { get; set; }
    public ImportacionAplicadaOsDto? Importacion { get; set; }
}

public record OrdenServicioGuardadaDto(long IdOs, string Numero, string Tipo, string Estado);

// ── Solicitud de edición y anulación (HU-40) ───────────────────────────────

public record PreparacionSolicitudEdicionOsDto(
    long IdOs, string Numero, string Tipo, string Estado, string? RazonSocial,
    long? IdAprobador, string? Aprobador, string? CargoAprobador, string? SedeAprobador, bool AprobadorDisponible,
    List<OpcionFiltroDto> Motivos);

public class SolicitarEdicionOsDto
{
    public int     IdMotivo   { get; set; }
    public string? Comentario { get; set; }
}

public class ResolverSolicitudEdicionOsDto
{
    public bool    Aprobar    { get; set; }
    /// <summary>Obligatorio al rechazar (mínimo 10 caracteres).</summary>
    public string? Comentario { get; set; }
}

/// <summary>Datos de una solicitud enviada o resuelta (para el correo y la respuesta).</summary>
public record SolicitudEdicionOsDto
{
    public long    IdSolicitud        { get; init; }
    public long    IdOs               { get; init; }
    public string  Numero             { get; init; } = "";
    public string  Tipo               { get; init; } = "OS";
    public string? RazonSocial        { get; init; }
    public string? Motivo             { get; init; }
    public string? Comentario         { get; init; }
    /// <summary>Quien la envió (solicitud) o la resolvió (resolución).</summary>
    public string? Autor              { get; init; }
    public bool?   Aprobada           { get; init; }
    public long?   IdDestinatario     { get; init; }
    public string? Destinatario       { get; init; }
    public string? CorreoDestinatario { get; init; }
    public bool    CorreoEnviado      { get; init; }
    public string? ErrorCorreo        { get; init; }
}

public record PersonalAsignadoOsDto(long IdUsuario, string Nombre, string? Rol, string? EstadoSsoma = null);

/// <summary>Modal Anular: impacto en la programación (recursos que se liberan) y motivos.</summary>
public record PreparacionAnulacionOsDto(
    long IdOs, string Numero, string Tipo, string Estado, string? RazonSocial,
    bool TieneProgramacion, string? Tecnico, DateTime? FechaEjecucion, string? HoraInicio, string? HoraFin,
    decimal? Viaticos, string? SimboloMoneda, List<PersonalAsignadoOsDto> Personal, List<OpcionFiltroDto> Motivos);

public class AnularOrdenServicioDto
{
    public int     IdMotivo   { get; set; }
    public string? Comentario { get; set; }
}

public record AnulacionOrdenServicioDto(long IdOs, string Numero, string Estado, int PersonalLiberado, int ViaticosLiberados);

// ── HU-42 Detalle ──────────────────────────────────────────────────────────

public record SolicitudPendienteOsDto(
    long IdSolicitud, string? Motivo, string? Comentario, DateTime? FechaSolicitud,
    long? IdSolicitante, string? Solicitante, long? IdAprobador, string? Aprobador);

public record AvanceEquipoOsDto(
    long IdOsEquipo, long IdEquipo, string CodigoTw, string Clasificacion, string ClasificacionLabel,
    string Marca, string Modelo, string NumSerie, string EstadoEjecucion, DateTime? FechaEjecucion, string? Observacion);

public record AvanceOrdenServicioDto(int Total, int Pendientes, int EnProceso, int Ejecutados, int Observados, decimal Porcentaje,
                                     List<AvanceEquipoOsDto> Equipos);

/// <summary>Cabecera + tab Resumen + Avance por equipos del Modal de Detalle.</summary>
public record DetalleOrdenServicioDto
{
    public long      IdOs                   { get; init; }
    public string    Tipo                   { get; init; } = "OS";
    public string    Numero                 { get; init; } = "";
    public string    Estado                 { get; init; } = "";
    public string    EstadoGrupo            { get; init; } = "";
    public string    EstadoLabel            { get; init; } = "";
    public long?     IdCliente              { get; init; }
    public string?   RazonSocial            { get; init; }
    public string?   Ruc                    { get; init; }
    public string?   DireccionOperaciones   { get; init; }
    public long?     IdContacto             { get; init; }
    public string?   Contacto               { get; init; }
    public string?   CargoContacto          { get; init; }
    public string?   TelefonoContacto       { get; init; }
    public string?   CorreoContacto         { get; init; }
    public long?     IdResponsable          { get; init; }
    public string?   Responsable            { get; init; }
    /// <summary>null en borrador.</summary>
    public DateTime? FechaEmision           { get; init; }
    public DateTime? FechaDocumento         { get; init; }
    /// <summary>Solo OS (en OM se oculta).</summary>
    public DateTime? FechaProgramadaDesde   { get; init; }
    public DateTime? FechaProgramadaHasta   { get; init; }
    /// <summary>Días hábiles (lunes a viernes) del rango programado.</summary>
    public int?      DiasHabilesEstimados   { get; init; }
    public long?     IdPropuesta            { get; init; }
    public string?   NumeroPropuesta        { get; init; }
    public int?      VersionPropuesta       { get; init; }
    public long?     IdRequerimiento        { get; init; }
    public string?   NumeroRq               { get; init; }
    /// <summary>Para los modales de Documentos (HU-31) e Historial de Auditoría (HU-32).</summary>
    public long?     IdExpediente           { get; init; }
    public int       NumeroEquipos          { get; init; }
    public int       NumeroConceptos        { get; init; }
    /// <summary>Chip amarillo "Solicitud de edición pendiente de aprobación".</summary>
    public SolicitudPendienteOsDto? SolicitudPendiente { get; init; }
    public bool      EdicionAprobada        { get; init; }
    public bool      PuedeEditar            { get; init; }
    public bool      PuedeSolicitarEdicion  { get; init; }
    public bool      PuedeResolverSolicitud { get; init; }
    public bool      PuedeAnular            { get; init; }
    public string?   MotivoAnulacion        { get; init; }
    public string?   ComentarioAnulacion    { get; init; }
    public DateTime? AnuladoEn              { get; init; }
    public string?   AnuladoPor             { get; init; }
    public DateTime? UltimaActualizacion    { get; init; }
    public string?   ActualizadoPor         { get; init; }
    public AvanceOrdenServicioDto Avance    { get; init; } = new(0, 0, 0, 0, 0, 0, []);
}

public record ProgramacionOrdenServicioDto(
    string Estado, bool TieneProgramacion, long? IdTecnico, string? Tecnico, DateTime? FechaEjecucion,
    string? HoraInicio, string? HoraFinEstimada, string? HoraLlegadaReal, string? HoraFinReal,
    string? EstadoPreparacion, bool ConfirmacionCliente, decimal? Viaticos, string? SimboloMoneda, string? NotasOperativas,
    List<PersonalAsignadoOsDto> Personal, string? Mensaje);

// ── HU-43 Buscadores ───────────────────────────────────────────────────────

public class FiltrosBuscarEquiposOsDto
{
    public long    IdCliente     { get; set; }
    /// <summary>La orden que se edita (no cuenta como "otra OS activa").</summary>
    public long?   IdOs          { get; set; }
    public string? Busqueda      { get; set; }
    /// <summary>equipo | instrumento | pesa.</summary>
    public string? Clasificacion { get; set; }
    public string? Ubicacion     { get; set; }
    /// <summary>Marca (y lista primero) los equipos cotizados en la propuesta de origen.</summary>
    public long?   IdPropuesta   { get; set; }
    public int     Pagina        { get; set; } = 1;
    public int     PorPagina     { get; set; } = 20;
}

public record BusquedaEquiposOsDto(List<EquipoOrdenServicioDto> Items, int Total, List<string> Ubicaciones, List<OpcionImportacionDto> Clasificaciones);

public class FiltrosBuscarConceptosOsDto
{
    public string? Busqueda  { get; set; }
    /// <summary>Tipo del suministro (catálogo TIPO_SUMINISTRO de clase servicio).</summary>
    public string? Tipo      { get; set; }
    /// <summary>Marca (y lista primero) los conceptos cotizados en la propuesta de origen.</summary>
    public long?   IdPropuesta { get; set; }
    public int     Pagina    { get; set; } = 1;
    public int     PorPagina { get; set; } = 20;
}

public record ConceptoCatalogoOsDto(long IdSuministro, string Codigo, string Descripcion, string? Tipo, string? TipoLabel,
                                    string? Subtipo, string? SubtipoLabel, bool AplicaServicio, bool AplicaMetrologia,
                                    bool DeLaPropuesta = false);

public record BusquedaConceptosOsDto(List<ConceptoCatalogoOsDto> Items, int Total, List<OpcionImportacionDto> Tipos);

// ── HU-44 Importación por Excel (plantilla oficial) ────────────────────────

public record EquipoImportacionOsDto
{
    public int     Fila              { get; init; }
    public string  CodigoTw          { get; init; } = "";
    /// <summary>ok | advertencia | error.</summary>
    public string  Estado            { get; init; } = "ok";
    public string? Mensaje           { get; init; }
    public EquipoOrdenServicioDto? Equipo { get; init; }
    /// <summary>Nombres de concepto escritos en el Excel.</summary>
    public List<string> ConceptosTexto { get; init; } = [];
    /// <summary>idSuministro de los conceptos reconocidos.</summary>
    public List<long>   Conceptos     { get; init; } = [];
}

public record ConceptoImportacionOsDto
{
    public int     Fila          { get; init; }
    public string  Texto         { get; init; } = "";
    public string  Estado        { get; init; } = "ok";
    public string? Mensaje       { get; init; }
    public long?   IdSuministro  { get; init; }
    public string? Codigo        { get; init; }
    public string? Descripcion   { get; init; }
    public string? Clasificacion { get; init; }
    /// <summary>Códigos TW de los equipos del Excel a los que aplica.</summary>
    public List<string> EquiposAplicados { get; init; } = [];
}

public record ResumenImportacionOsDto(int ConceptosOk, int ConceptosAdvertencia, int ConceptosError,
                                      int EquiposOk, int EquiposAdvertencia, int EquiposError, int Relaciones);

public record AnalisisImportacionOsDto
{
    public string NombreArchivo { get; init; } = "";
    public ResumenImportacionOsDto Resumen { get; init; } = new(0, 0, 0, 0, 0, 0, 0);
    /// <summary>false si hay errores: el botón Confirmar queda deshabilitado hasta corregir el archivo.</summary>
    public bool   PuedeConfirmar { get; init; }
    public List<ConceptoImportacionOsDto> Conceptos { get; init; } = [];
    public List<EquipoImportacionOsDto>   Equipos   { get; init; } = [];
}

/// <summary>Lo que devuelve SP_ObtenerCandidatosImportacionOrdenServicio.</summary>
public record CandidatosImportacionOsDto(
    List<EquipoOrdenServicioDto> Equipos,
    List<(string CodigoTw, string Motivo)> NoDisponibles,
    List<ConceptoCatalogoOsDto> Conceptos);

// ── HU-40 Modal "Elegir Propuesta Aceptada" ────────────────────────────────

public class FiltrosPropuestasDisponiblesOsDto
{
    /// <summary>N° de propuesta, N° de RQ, cliente o RUC.</summary>
    public string? Busqueda  { get; set; }
    /// <summary>OS | OM (vacío = ambos).</summary>
    public string? Tipo      { get; set; }
    public int     Pagina    { get; set; } = 1;
    public int     PorPagina { get; set; } = 10;
}

/// <summary>Propuesta aceptada sin OS/OM activa.</summary>
public record PropuestaDisponibleOsDto
{
    public long      IdPropuesta        { get; init; }
    public string    Numero             { get; init; } = "";
    public int       Version            { get; init; }
    public string?   TipoServicio       { get; init; }
    /// <summary>OS u OM que se generará (Metrología → OM).</summary>
    public string    Tipo               { get; init; } = "OS";
    public long      IdCliente          { get; init; }
    public string    RazonSocial        { get; init; } = "";
    public string?   Ruc                { get; init; }
    public string?   Sede               { get; init; }
    public long?     IdRequerimiento    { get; init; }
    public string?   NumeroRequerimiento { get; init; }
    public string?   Area               { get; init; }
    public long?     IdResponsable      { get; init; }
    public string?   Responsable        { get; init; }
    public DateTime? FechaAceptacion    { get; init; }
    /// <summary>Referencial.</summary>
    public decimal?  MontoTotal         { get; init; }
    public string?   SimboloMoneda      { get; init; }
    public int       EquiposCotizados   { get; init; }
    public int       ConceptosCotizados { get; init; }
}

public record PropuestasDisponiblesOsDto(List<PropuestaDisponibleOsDto> Items, int Total, int Pagina, int PorPagina);

/// <summary>Body de aprobar / rechazar una solicitud de edición (rechazar: comentario obligatorio, mín. 10).</summary>
public class ComentarioSolicitudOsDto
{
    public string? Comentario { get; set; }
}
