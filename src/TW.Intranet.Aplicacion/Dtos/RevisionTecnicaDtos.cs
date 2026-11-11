namespace TW.Intranet.Aplicacion.Dtos;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Revisión Técnica (Sprint 5, HU-56 a HU-59) — informes de servicio técnico que revisa el Supervisor / Jefe de Servicio Técnico.
// Estados (GrupoEstado): pendiente_revision · pendiente_precotizacion · revisado_sin_precot · revisado_con_precot.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── HU-56 Bandeja ──────────────────────────────────────────────────────────────────────────────

/// <summary>Filtros de la bandeja (query string).</summary>
public class FiltrosBandejaInformesDto
{
    /// <summary>todos (defecto) · pendientes · revisados · pendiente_revision · pendiente_precotizacion · revisado_sin_precot · revisado_con_precot.</summary>
    public string?   Grupo            { get; set; }
    /// <summary>N° OS, cliente, RUC, técnico, equipo, código TW o N° de serie.</summary>
    public string?   Busqueda         { get; set; }
    public long?     IdTecnico        { get; set; }
    public long?     IdCliente        { get; set; }
    /// <summary>true = con observaciones, false = sin observaciones, vacío = todos.</summary>
    public bool?     ConObservaciones { get; set; }
    /// <summary>true = solo los que superaron el SLA de revisión.</summary>
    public bool      SlaVencido       { get; set; }
    /// <summary>Fecha de ejecución.</summary>
    public DateTime? FechaDesde       { get; set; }
    public DateTime? FechaHasta       { get; set; }
    public int       Pagina           { get; set; } = 1;
    public int       PorPagina        { get; set; } = 10;
}

/// <summary>Las 4 tarjetas de la bandeja (+ SLA vencidos).</summary>
public class TarjetasInformesDto
{
    public int PendientesRevision      { get; init; }
    public int PendientesPrecotizacion { get; init; }
    public int RevisadosSinPrecot      { get; init; }
    public int RevisadosConPrecot      { get; init; }
    public int SlaVencidos             { get; init; }
    public int SlaHoras                { get; init; }
}

public class ItemBandejaInformeDto
{
    public long      IdInforme               { get; init; }
    public string?   NumeroInforme           { get; init; }
    public int       Version                 { get; init; }
    public long?     IdOs                    { get; init; }
    public string?   NumeroOs                { get; init; }
    public string?   TipoOs                  { get; init; }
    public DateTime? FechaEjecucion          { get; init; }
    public long?     IdCliente               { get; init; }
    public string?   RazonSocial             { get; init; }
    public string?   Ruc                     { get; init; }
    public string?   Sede                    { get; init; }
    public long?     IdEquipo                { get; init; }
    public string?   Equipo                  { get; init; }
    public string?   CodigoTw                { get; init; }
    public string?   NumeroSerie             { get; init; }
    public string?   TipoEquipo              { get; init; }
    public string?   TipoServicio            { get; init; }
    public long?     IdTecnico               { get; init; }
    public string?   Tecnico                 { get; init; }
    public int       NObservaciones          { get; init; }
    public bool      ConObservaciones        { get; init; }
    /// <summary>Estado en BD: pendiente_revision · en_revision · revisado.</summary>
    public string?   Estado                  { get; init; }
    public string?   GrupoEstado             { get; init; }
    public string?   EstadoLabel             { get; init; }
    public long?     IdPrecotizacion         { get; init; }
    public string?   NumeroPrecot            { get; init; }
    public long?     IdPropuestaDerivada     { get; init; }
    public string?   NumeroPropuestaDerivada { get; init; }
    public DateTime? FechaEnvioRevision      { get; init; }
    /// <summary>Horas desde que llegó a la bandeja (hasta la revisión, si ya se revisó).</summary>
    public int?      HorasEspera             { get; init; }
    public int?      SlaHoras                { get; init; }
    public bool      SlaVencido              { get; init; }
    public DateTime? FechaRevision           { get; init; }
    public string?   Revisor                 { get; init; }
}

public class OpcionInformeDto
{
    public long    Id     { get; init; }
    public string? Nombre { get; init; }
}

public record BandejaInformesDto(
    TarjetasInformesDto             Tarjetas,
    List<ItemBandejaInformeDto>     Items,
    int                             Total,
    int                             Pagina,
    int                             PorPagina,
    List<OpcionInformeDto>          Tecnicos,
    List<OpcionInformeDto>          Clientes);

// ── HU-57 Detalle ──────────────────────────────────────────────────────────────────────────────

/// <summary>Resumen, información general, validaciones, diagnóstico, resultado de ensayos, trazabilidad y acciones.</summary>
public class CabeceraInformeDto
{
    public long      IdInforme                 { get; init; }
    public string?   NumeroInforme             { get; init; }
    public int       Version                   { get; init; }
    public string?   Estado                    { get; init; }
    public string?   GrupoEstado               { get; init; }
    public string?   EstadoLabel               { get; init; }
    /// <summary>"Descargar Informe PDF" (lo genera la app móvil).</summary>
    public string?   UrlPdf                    { get; init; }
    public long?     IdOs                      { get; init; }
    public string?   NumeroOs                  { get; init; }
    public string?   TipoOs                    { get; init; }
    public long?     IdCliente                 { get; init; }
    public string?   RazonSocial               { get; init; }
    public string?   Ruc                       { get; init; }
    public long?     IdSede                    { get; init; }
    public string?   Sede                      { get; init; }
    public long?     IdEquipo                  { get; init; }
    public string?   Equipo                    { get; init; }
    public string?   CodigoTw                  { get; init; }
    public string?   NumeroSerie               { get; init; }
    public string?   Marca                     { get; init; }
    public string?   Modelo                    { get; init; }
    /// <summary>"Tipo balanza" (clasificación del equipo).</summary>
    public string?   TipoEquipo                { get; init; }
    public int?      IdTipoServicio            { get; init; }
    public string?   TipoServicio              { get; init; }
    public long?     IdTecnico                 { get; init; }
    public string?   Tecnico                   { get; init; }
    public DateTime? FechaEjecucion            { get; init; }
    public string?   HoraInicio                { get; init; }
    public string?   HoraFin                   { get; init; }
    public int?      DuracionMin               { get; init; }
    public long?     IdPropuesta               { get; init; }
    public string?   NumeroPropuesta           { get; init; }
    public int?      VersionPropuesta          { get; init; }
    public long?     IdRequerimiento           { get; init; }
    public string?   NumeroRq                  { get; init; }
    /// <summary>Contacto en sitio.</summary>
    public string?   Contacto                  { get; init; }
    /// <summary>Resumen del diagnóstico.</summary>
    public string?   Diagnostico               { get; init; }

    // Resumen de validaciones
    public int       NFotos                    { get; init; }
    public int       NFotosValidas             { get; init; }
    public int       NEnsayos                  { get; init; }
    public int       NEnsayosSinResultado      { get; init; }
    public int       NEnsayosNoConformes       { get; init; }
    public int       NObservaciones            { get; init; }
    public int       NRecomendaciones          { get; init; }
    public int       NPasos                    { get; init; }
    public int       NPasosRealizados          { get; init; }
    public decimal?  PorcentajeProcedimiento   { get; init; }
    /// <summary>sin_registro · incompletos · completos.</summary>
    public string?   EstadoEnsayos             { get; init; }
    /// <summary>no_aplica · requiere_precotizacion · precotizacion_enviada · convertida.</summary>
    public string?   OportunidadComercial      { get; init; }

    // Resultado global de los ensayos
    public string?   Normativa                 { get; init; }
    public string?   PatronEnsayo              { get; init; }
    public decimal?  ToleranciaExcentricidad   { get; init; }
    /// <summary>dentro · fuera (de tolerancia).</summary>
    public string?   ResultadoGlobal           { get; init; }
    public decimal?  ErrorMaximo               { get; init; }
    public string?   ErrorMaximoDetalle        { get; init; }
    public decimal?  Incertidumbre             { get; init; }
    public decimal?  FactorK                   { get; init; }
    public string?   DecisionTecnica           { get; init; }
    public string?   DescripcionComplementaria { get; init; }

    // Trazabilidad
    public DateTime? FechaEnvioRevision        { get; init; }
    public DateTime? FechaInicioRevision       { get; init; }
    public DateTime? FechaRevision             { get; init; }
    public long?     IdRevisor                 { get; init; }
    public string?   Revisor                   { get; init; }
    public string?   NotaRevision              { get; init; }
    public int?      HorasEspera               { get; init; }
    public int?      SlaHoras                  { get; init; }
    public bool      SlaVencido                { get; init; }
    public long?     IdPrecotizacion           { get; init; }
    public string?   NumeroPrecot              { get; init; }
    public string?   EstadoPrecot              { get; init; }
    public DateTime? FechaPrecot               { get; init; }
    public string?   AutorPrecot               { get; init; }
    public int?      NItemsPrecot              { get; init; }
    public string?   NotaPrecotizacion         { get; init; }
    public long?     IdPropuestaDerivada       { get; init; }
    public string?   NumeroPropuestaDerivada   { get; init; }
    public int?      VersionPropuestaDerivada  { get; init; }
    public string?   EstadoPropuestaDerivada   { get; init; }

    // Acciones
    public bool      PuedeEditar               { get; init; }
    public bool      PuedeRegistrarPrecotizacion { get; init; }
    public bool      PuedeRegistrarRevision    { get; init; }
    /// <summary>Aviso ámbar: "Este servicio tiene observaciones registradas. Debes registrar la precotización…".</summary>
    public string?   MensajeBloqueo            { get; init; }
    /// <summary>Botón principal del modal: registrar_precotizacion · registrar_revision · null (revisado).</summary>
    public string?   AccionPrincipal           { get; init; }
}

public class PasoInformeDto
{
    public long    IdPaso    { get; init; }
    public int     Orden     { get; init; }
    public string? Titulo    { get; init; }
    public string? Detalle   { get; init; }
    public bool    Realizado { get; init; }
    public string? Nota      { get; init; }
    /// <summary>tecnico · supervisor.</summary>
    public string? Origen    { get; init; }
}

public class EnsayoInformeDto
{
    public long     IdEnsayo       { get; init; }
    /// <summary>pesaje · excentricidad.</summary>
    public string?  Tipo           { get; init; }
    public int      Orden          { get; init; }
    /// <summary>Pesaje: carga (kg). Excentricidad: posición en la plataforma.</summary>
    public string?  Punto          { get; init; }
    /// <summary>"CAP. MÁX", "RETORNO A CERO"…</summary>
    public string?  NotaPunto      { get; init; }
    public decimal? Carga          { get; init; }
    public decimal? Lectura        { get; init; }
    /// <summary>Pesaje: error en %. Excentricidad: desviación en kg.</summary>
    public decimal? Error          { get; init; }
    public decimal? Tolerancia     { get; init; }
    /// <summary>conforme · no_conforme.</summary>
    public string?  Resultado      { get; init; }
    /// <summary>Dentro / Fuera (pesaje) · Conforme / No conforme (excentricidad).</summary>
    public string?  ResultadoLabel { get; init; }
    public string?  Origen         { get; init; }
}

public class ObservacionInformeDto
{
    public long    IdObservacion   { get; init; }
    public string? Codigo          { get; init; }
    public int     Orden           { get; init; }
    public string? Titulo          { get; init; }
    public string? Descripcion     { get; init; }
    public string? Ubicacion       { get; init; }
    public string? DetalleExtra    { get; init; }
    /// <summary>critico · alto · medio · bajo.</summary>
    public string? NivelAfectacion { get; init; }
    public long?   IdEvidencia     { get; init; }
    public string? UrlFoto         { get; init; }
    public string? Origen          { get; init; }
}

public class RecomendacionInformeDto
{
    public long    IdRecomendacion   { get; init; }
    public string? Codigo            { get; init; }
    public int     Orden             { get; init; }
    public string? Titulo            { get; init; }
    public string? Descripcion       { get; init; }
    /// <summary>alta · media · baja.</summary>
    public string? Prioridad         { get; init; }
    /// <summary>Plazo sugerido ("Inmediato (&lt; 48h)", "Próximo mantenimiento").</summary>
    public string? Plazo             { get; init; }
    public long?   IdObservacion     { get; init; }
    public string? CodigoObservacion { get; init; }
    public string? Origen            { get; init; }
}

public class FotoInformeDto
{
    public long      IdEvidencia       { get; init; }
    public string?   UrlArchivo        { get; init; }
    public string?   Descripcion       { get; init; }
    /// <summary>ANTES · DURANTE · DESPUES · FALLA · VERIFICACION (filtros de la galería).</summary>
    public string?   Momento           { get; init; }
    public string?   MomentoLabel      { get; init; }
    public DateTime? FechaCaptura      { get; init; }
    public decimal?  Latitud           { get; init; }
    public decimal?  Longitud          { get; init; }
    public bool      Georreferenciada  { get; init; }
    public string?   ValidacionIa      { get; init; }
    /// <summary>true = la evidencia es un video MP4 (el momento de encendido): la miniatura se pide con ?cuadro=true y el visor reproduce el archivo sin cuadro.</summary>
    public bool      EsVideo           { get; init; }
    public long?     IdObservacion     { get; init; }
    public string?   CodigoObservacion { get; init; }
}

public class ItemPrecotizacionDto
{
    public long     IdItem             { get; init; }
    public int      Orden              { get; init; }
    public string?  Concepto           { get; init; }
    public string?  Codigo             { get; init; }
    public long?    IdSuministro       { get; init; }
    public string?  DescripcionTecnica { get; init; }
    public decimal  Cantidad           { get; init; }
    public string?  Unidad             { get; init; }
    /// <summary>alta · media · opcional.</summary>
    public string?  Prioridad          { get; init; }
    public long?    IdObservacion      { get; init; }
    public string?  CodigoObservacion  { get; init; }
    /// <summary>Solo en el detalle de Comercial (precio de referencia del catálogo).</summary>
    public decimal? PrecioReferencia   { get; init; }
}

public class EventoRecienteDto
{
    public long      IdAuditoria { get; init; }
    public string?   Accion      { get; init; }
    public string?   Descripcion { get; init; }
    public DateTime? Fecha       { get; init; }
    public string?   Usuario     { get; init; }
}

public record DetalleInformeTecnicoDto(
    CabeceraInformeDto            Cabecera,
    List<PasoInformeDto>          Procedimiento,
    List<EnsayoInformeDto>        Ensayos,
    List<ObservacionInformeDto>   Observaciones,
    List<RecomendacionInformeDto> Recomendaciones,
    List<FotoInformeDto>          Fotos,
    List<ItemPrecotizacionDto>    Precotizacion,
    List<EventoRecienteDto>       HistorialReciente);

// ── HU-58 Edición ──────────────────────────────────────────────────────────────────────────────

/// <summary>
/// "Guardar cambios" de la edición (pasos 1 a 4). Cada sección es opcional: null = no cambia. Una lista enviada es la lista
/// completa de esa sección (con Id = se actualiza, sin Id = se agrega, las que faltan se eliminan).
/// DescripcionComplementaria: null = no cambia, "" = se borra.
/// </summary>
public class GuardarInformeTecnicoDto
{
    public string?                        DescripcionComplementaria { get; set; }
    public ResultadoEnsayosGuardarDto?    Resultado                 { get; set; }
    public List<PasoGuardarDto>?          Procedimiento             { get; set; }
    public List<EnsayoGuardarDto>?        Ensayos                   { get; set; }
    public List<ObservacionGuardarDto>?   Observaciones             { get; set; }
    public List<RecomendacionGuardarDto>? Recomendaciones           { get; set; }
}

public class ResultadoEnsayosGuardarDto
{
    public string?  Normativa               { get; set; }
    public string?  PatronEnsayo            { get; set; }
    public decimal? ToleranciaExcentricidad { get; set; }
    /// <summary>dentro · fuera.</summary>
    public string?  ResultadoGlobal         { get; set; }
    public decimal? ErrorMaximo             { get; set; }
    public string?  ErrorMaximoDetalle      { get; set; }
    public decimal? Incertidumbre           { get; set; }
    public decimal? FactorK                 { get; set; }
    public string?  DecisionTecnica         { get; set; }
}

public class PasoGuardarDto
{
    public long?   Id        { get; set; }
    public string? Titulo    { get; set; }
    public string? Detalle   { get; set; }
    public bool    Realizado { get; set; } = true;
    public string? Nota      { get; set; }
}

public class EnsayoGuardarDto
{
    public long?    Id         { get; set; }
    /// <summary>pesaje · excentricidad.</summary>
    public string?  Tipo       { get; set; }
    public string?  Punto      { get; set; }
    public string?  NotaPunto  { get; set; }
    public decimal? Carga      { get; set; }
    public decimal? Lectura    { get; set; }
    public decimal? Error      { get; set; }
    public decimal? Tolerancia { get; set; }
    /// <summary>conforme · no_conforme. Vacío con Error y Tolerancia: se calcula (|error| ≤ tolerancia → conforme).</summary>
    public string?  Resultado  { get; set; }
}

public class ObservacionGuardarDto
{
    public long?   Id              { get; set; }
    public string? Titulo          { get; set; }
    public string? Descripcion     { get; set; }
    public string? Ubicacion       { get; set; }
    public string? DetalleExtra    { get; set; }
    /// <summary>critico · alto · medio · bajo.</summary>
    public string? NivelAfectacion { get; set; }
    /// <summary>Foto del servicio vinculada a la observación.</summary>
    public long?   IdEvidencia     { get; set; }
}

public class RecomendacionGuardarDto
{
    public long?   Id                { get; set; }
    public string? Titulo            { get; set; }
    public string? Descripcion       { get; set; }
    /// <summary>alta · media · baja.</summary>
    public string? Prioridad         { get; set; }
    public string? Plazo             { get; set; }
    /// <summary>Observación ya guardada.</summary>
    public long?   IdObservacion     { get; set; }
    /// <summary>Para vincular una observación NUEVA de este mismo guardado: su posición (desde 0) en Observaciones.</summary>
    public int?    IndiceObservacion { get; set; }
}

public record InformeGuardadoDto(long IdInforme, int CambiosRegistrados, string? Estado);

/// <summary>Paso 4: precotización (obligatoria si el servicio tiene observaciones). Items = lista completa.</summary>
public class GuardarPrecotizacionInformeDto
{
    /// <summary>Observaciones del supervisor para Comercial (se copian como nota en la nueva propuesta).</summary>
    public string?                           Nota  { get; set; }
    public List<ItemPrecotizacionGuardarDto> Items { get; set; } = [];
}

public class ItemPrecotizacionGuardarDto
{
    public long?    Id                 { get; set; }
    /// <summary>Concepto / repuesto (si viene IdSuministro y está vacío, se toma del catálogo).</summary>
    public string?  Concepto           { get; set; }
    public string?  Codigo             { get; set; }
    public long?    IdSuministro       { get; set; }
    public string?  DescripcionTecnica { get; set; }
    public decimal  Cantidad           { get; set; } = 1;
    /// <summary>un · serv · m…</summary>
    public string?  Unidad             { get; set; }
    /// <summary>alta · media · opcional.</summary>
    public string?  Prioridad          { get; set; }
    public long?    IdObservacion      { get; set; }
}

public record PrecotizacionGuardadaDto(long IdPrecotizacion, string Numero, int Items, string Estado);

// ── HU-59 Revisión e historial ─────────────────────────────────────────────────────────────────

public class CabeceraRevisionInformeDto
{
    public long    IdInforme            { get; init; }
    public string? NumeroOs             { get; init; }
    public string? RazonSocial          { get; init; }
    public string? Equipo               { get; init; }
    public string? Tecnico              { get; init; }
    public int     Verificados          { get; init; }
    public int     Total                { get; init; }
    /// <summary>false si falta un punto obligatorio del checklist.</summary>
    public bool    PuedeConfirmar       { get; init; }
    public string? Aviso                { get; init; }
    public string? ImpactoInforme       { get; init; }
    public string? ImpactoPrecotizacion { get; init; }
    public string? ImpactoEstado        { get; init; }
    public string? ImpactoNotificacion  { get; init; }
}

public class ItemChecklistRevisionDto
{
    public int     Orden       { get; init; }
    /// <summary>fotos · ensayos · observaciones · precotizacion · procedimiento.</summary>
    public string? Codigo      { get; init; }
    public string? Titulo      { get; init; }
    public string? Detalle     { get; init; }
    public bool    Cumple      { get; init; }
    public bool    Obligatorio { get; init; }
}

public record PreparacionRevisionInformeDto(CabeceraRevisionInformeDto Cabecera, List<ItemChecklistRevisionDto> Checklist);

public class RegistrarRevisionInformeDto
{
    /// <summary>Nota interna del supervisor (opcional, hasta 500 caracteres).</summary>
    public string? Nota { get; set; }
}

public class InformeRevisadoDto
{
    public long      IdInforme           { get; init; }
    public string?   Estado              { get; init; }
    public DateTime? FechaRevision       { get; init; }
    public long?     IdPrecotizacion     { get; init; }
    public string?   NumeroPrecotizacion { get; init; }
}

public class ContadoresHistorialInformeDto
{
    public int Todos         { get; init; }
    public int Edicion       { get; init; }
    public int Precotizacion { get; init; }
    public int Revision      { get; init; }
    public int Sistema       { get; init; }
}

public class EventoHistorialInformeDto
{
    public long      IdAuditoria { get; init; }
    public DateTime? Dia         { get; init; }
    public DateTime? Fecha       { get; init; }
    public string?   Accion      { get; init; }
    /// <summary>edicion · precotizacion · revision · sistema.</summary>
    public string?   Categoria   { get; init; }
    /// <summary>movil · sistema · intranet.</summary>
    public string?   Origen      { get; init; }
    /// <summary>Chip: Móvil · Sistema · Supervisor Técnico · Edición · Comercial…</summary>
    public string?   Etiqueta    { get; init; }
    public long?     IdUsuario   { get; init; }
    public string?   Usuario     { get; init; }
    public string?   Descripcion { get; init; }
    /// <summary>"Modificaciones aplicadas".</summary>
    public string?   Cambios     { get; init; }
    public string?   Detalle     { get; init; }
    public string?   Nota        { get; init; }
}

public record HistorialInformeDto(ContadoresHistorialInformeDto Contadores, List<EventoHistorialInformeDto> Eventos);

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HU-60 Precotizaciones Técnicas (CRM)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

public class FiltrosPrecotizacionesDto
{
    /// <summary>todas (defecto) · pendiente · convertida.</summary>
    public string?   Estado       { get; set; }
    /// <summary>RQ, cliente, RUC, supervisor, equipo, OS o N° de precotización.</summary>
    public string?   Busqueda     { get; set; }
    public long?     IdSupervisor { get; set; }
    public DateTime? FechaDesde   { get; set; }
    public DateTime? FechaHasta   { get; set; }
    public int       Pagina       { get; set; } = 1;
    public int       PorPagina    { get; set; } = 10;
}

public class TarjetasPrecotizacionesDto
{
    public int      Pendientes          { get; init; }
    public int      ConvertidasMes      { get; init; }
    public decimal? TiempoPromedioHoras { get; init; }
    public int      MetaHoras           { get; init; }
    public int      Supervisores        { get; init; }
    public string?  NombresSupervisores { get; init; }
}

public class ItemBandejaPrecotizacionDto
{
    public long      IdPrecotizacion          { get; init; }
    public string?   Numero                   { get; init; }
    public DateTime? Fecha                    { get; init; }
    public long?     IdRequerimiento          { get; init; }
    public string?   NumeroRq                 { get; init; }
    public long?     IdCliente                { get; init; }
    public string?   RazonSocial              { get; init; }
    public string?   Ruc                      { get; init; }
    public string?   Sede                     { get; init; }
    public long?     IdEquipo                 { get; init; }
    public string?   Equipo                   { get; init; }
    public long?     IdSupervisor             { get; init; }
    public string?   Supervisor               { get; init; }
    public int       Items                    { get; init; }
    public int       Observaciones            { get; init; }
    public string?   Estado                   { get; init; }
    /// <summary>pendiente · convertida.</summary>
    public string?   EstadoGrupo              { get; init; }
    public string?   EstadoLabel              { get; init; }
    public long?     IdOs                     { get; init; }
    public string?   NumeroOs                 { get; init; }
    public long?     IdInforme                { get; init; }
    public long?     IdPropuestaGenerada      { get; init; }
    public string?   NumeroPropuestaGenerada  { get; init; }
    public int?      VersionPropuestaGenerada { get; init; }
}

public record BandejaPrecotizacionesDto(
    TarjetasPrecotizacionesDto        Tarjetas,
    List<ItemBandejaPrecotizacionDto> Items,
    int                               Total,
    int                               Pagina,
    int                               PorPagina,
    List<OpcionInformeDto>            Supervisores);

public class CabeceraPrecotizacionDto
{
    public long      IdPrecotizacion            { get; init; }
    public string?   Numero                     { get; init; }
    public string?   Estado                     { get; init; }
    public string?   EstadoGrupo                { get; init; }
    public string?   EstadoLabel                { get; init; }
    public string?   EstadoDetalle              { get; init; }
    public DateTime? Fecha                      { get; init; }
    public string?   NotaSupervisor             { get; init; }
    /// <summary>Resumen del servicio de origen (diagnóstico).</summary>
    public string?   Diagnostico                { get; init; }
    public long?     IdRequerimiento            { get; init; }
    public string?   NumeroRq                   { get; init; }
    public DateTime? FechaRq                    { get; init; }
    public long?     IdCliente                  { get; init; }
    public string?   RazonSocial                { get; init; }
    public string?   Ruc                        { get; init; }
    public long?     IdSede                     { get; init; }
    public string?   Sede                       { get; init; }
    public long?     IdEquipo                   { get; init; }
    public string?   Equipo                     { get; init; }
    public string?   Marca                      { get; init; }
    public string?   Modelo                     { get; init; }
    public string?   CodigoTw                   { get; init; }
    public string?   NumeroSerie                { get; init; }
    public long?     IdSupervisor               { get; init; }
    public string?   Supervisor                 { get; init; }
    public string?   CargoSupervisor            { get; init; }
    public long?     IdInforme                  { get; init; }
    public int?      VersionInforme             { get; init; }
    public long?     IdOs                       { get; init; }
    public string?   NumeroOs                   { get; init; }
    public DateTime? FechaEjecucion             { get; init; }
    public string?   TipoServicio               { get; init; }
    public int       Items                      { get; init; }
    public int       Observaciones              { get; init; }
    public long?     IdPropuestaGenerada        { get; init; }
    public string?   NumeroPropuestaGenerada    { get; init; }
    public int?      VersionPropuestaGenerada   { get; init; }
    public string?   EstadoPropuestaGenerada    { get; init; }
    public decimal?  TotalPropuestaGenerada     { get; init; }
    public string?   MonedaPropuestaGenerada    { get; init; }
    public string?   ComercialPropuestaGenerada { get; init; }
    public DateTime? FechaConversion            { get; init; }
    public string?   ConvertidoPor              { get; init; }
    public decimal?  HorasAtencion              { get; init; }
    public long?     IdPropuestaOrigen          { get; init; }
    public string?   NumeroPropuestaOrigen      { get; init; }
    public int?      VersionPropuestaOrigen     { get; init; }
    public bool      PuedeConvertir             { get; init; }
    public string?   MensajeConversion          { get; init; }
}

public class ObservacionPrecotizacionDto
{
    public long    IdObservacion   { get; init; }
    public string? Codigo          { get; init; }
    public string? Titulo          { get; init; }
    public string? Descripcion     { get; init; }
    public string? Ubicacion       { get; init; }
    public string? NivelAfectacion { get; init; }
}

public class PasoTrazabilidadPrecotizacionDto
{
    public int       Orden      { get; init; }
    /// <summary>rq · propuesta_origen · oc · os · precotizacion · propuesta_derivada.</summary>
    public string?   Codigo     { get; init; }
    public string?   Titulo     { get; init; }
    public string?   Detalle    { get; init; }
    public DateTime? Fecha      { get; init; }
    public bool      Completado { get; init; }
    public bool      Actual     { get; init; }
}

public record DetallePrecotizacionDto(
    CabeceraPrecotizacionDto               Cabecera,
    List<ObservacionPrecotizacionDto>      Observaciones,
    List<ItemPrecotizacionDto>             Items,
    List<PasoTrazabilidadPrecotizacionDto> Trazabilidad);

public class CabeceraPrecargaPrecotizacionDto
{
    public long      IdPrecotizacion  { get; init; }
    public string?   Numero           { get; init; }
    public long?     IdRequerimiento  { get; init; }
    public string?   NumeroRq         { get; init; }
    public long?     IdCliente        { get; init; }
    public string?   RazonSocial      { get; init; }
    public string?   Ruc              { get; init; }
    public long?     IdContacto       { get; init; }
    public string?   Contacto         { get; init; }
    public long?     IdSede           { get; init; }
    public string?   Sede             { get; init; }
    public long?     IdOs             { get; init; }
    public string?   NumeroOs         { get; init; }
    public long?     IdExpediente     { get; init; }
    public string?   NumeroExpediente { get; init; }
    public long?     IdSupervisor     { get; init; }
    public string?   Supervisor       { get; init; }
    public DateTime? Fecha            { get; init; }
    public string?   Equipo           { get; init; }
    public string?   TipoServicio     { get; init; }
    /// <summary>"Observaciones del supervisor en planta" (se copia como nota de la propuesta).</summary>
    public string?   Nota             { get; init; }
    public int       Items            { get; init; }
}

public class ItemPrecargaPrecotizacionDto
{
    public long     IdItem             { get; init; }
    public int      Orden              { get; init; }
    public string?  Concepto           { get; init; }
    public string?  Codigo             { get; init; }
    public long?    IdSuministro       { get; init; }
    /// <summary>Texto listo para la descripción del ítem de la propuesta.</summary>
    public string?  Descripcion        { get; init; }
    public string?  DescripcionTecnica { get; init; }
    public decimal  Cantidad           { get; init; }
    public string?  Unidad             { get; init; }
    public string?  Prioridad          { get; init; }
    /// <summary>principal · opcional (prioridad "opcional" → sección opcional de la propuesta).</summary>
    public string?  Seccion            { get; init; }
    public decimal? PrecioReferencia   { get; init; }
    public int?     IdMonedaReferencia { get; init; }
    public string?  CodigoObservacion  { get; init; }
}

public record PrecargaPrecotizacionDto(CabeceraPrecargaPrecotizacionDto Cabecera, List<ItemPrecargaPrecotizacionDto> Items);

public class ConvertirPrecotizacionDto
{
    /// <summary>Propuesta creada a partir de la precotización (mismo cliente y RQ).</summary>
    public long IdPropuesta { get; set; }
}

public class PrecotizacionConvertidaDto
{
    public long    IdPrecotizacion  { get; init; }
    public string? Numero           { get; init; }
    public string? Estado           { get; init; }
    public long    IdPropuesta      { get; init; }
    public string? NumeroPropuesta  { get; init; }
    public int?    VersionPropuesta { get; init; }
}
