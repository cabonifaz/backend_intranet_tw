namespace TW.Intranet.Aplicacion.Dtos;

// ══════════════════════ HU-17 — Bandeja de Seguimiento Comercial ══════════════════════

/// <summary>
/// Filtros de la bandeja de seguimiento.
/// Estado: abiertas (vacío = por defecto) | en_seguimiento | sin_respuesta | requiere_ajuste | vencidos |
/// aceptada | rechazada | oc_pendientes | aceptadas_mes | rechazadas_mes | todas.
/// Cada tarjeta KPI tiene su filtro equivalente.
/// </summary>
public record FiltrosBandejaSeguimientoDto
{
    public long?   IdResponsable { get; init; }
    public string? Estado        { get; init; }
    public string? Busqueda      { get; init; }
    public int     Pagina        { get; init; } = 1;
    public int     PorPagina     { get; init; } = 10;
}

/// <summary>Tarjetas del pipeline. TendenciaRechazadas: alza | baja | estable (vs. mes anterior).</summary>
public record KpisSeguimientoDto(
    int     EnSeguimiento,
    decimal VariacionEnSeguimientoPct,
    int     SinRespuesta,
    int     SeguimientosVencidos,
    int     AceptadasMes,
    int     MetaAceptadasMes,
    int     RechazadasMes,
    int     RechazadasMesAnterior,
    string  TendenciaRechazadas,
    int     OcPendientes);

public record ItemBandejaSeguimientoDto
{
    public long      IdPropuesta           { get; init; }
    public string    Numero                { get; init; } = "";
    public int       Version               { get; init; }
    public long?     IdRequerimiento       { get; init; }
    public string?   NumeroRq              { get; init; }
    public long      IdCliente             { get; init; }
    public string    RazonSocial           { get; init; } = "";
    public string?   Ruc                   { get; init; }
    public long?     IdContacto            { get; init; }
    /// <summary>null = sin contacto registrado (el front muestra "Sin respuesta" / "—").</summary>
    public string?   Contacto              { get; init; }
    public string?   CargoContacto         { get; init; }
    public string?   TelefonoContacto      { get; init; }
    public string?   CorreoContacto        { get; init; }
    public decimal   Total                 { get; init; }
    public int       IdMoneda              { get; init; }
    public string?   Moneda                { get; init; }
    public string?   MonedaSimbolo         { get; init; }
    public DateTime? FechaEnvio            { get; init; }
    /// <summary>Días desde el envío al cliente (columna DÍAS).</summary>
    public int       DiasTranscurridos     { get; init; }
    /// <summary>Días desde la última respuesta efectiva del cliente (o desde el envío).</summary>
    public int       DiasSinRespuesta      { get; init; }
    public long      IdResponsable         { get; init; }
    public string?   Responsable           { get; init; }
    public int       Interacciones         { get; init; }
    public DateTime? FechaUltimaInteraccion { get; init; }
    public string?   CanalUltimo           { get; init; }
    public string?   ResultadoUltimoCodigo { get; init; }
    public string?   ResultadoUltimo       { get; init; }
    /// <summary>LLAMADA | CORREO | REUNION | VISITA | REENVIO_AJUSTES | GENERAR_OC | OTRO |
    /// PRIMER_SEGUIMIENTO | PROGRAMAR_SEGUIMIENTO | VALIDAR_OC · null = sin acción pendiente.</summary>
    public string?   ProximaAccionCodigo   { get; init; }
    public string?   ProximaAccion         { get; init; }
    public string?   ProximaAccionDetalle  { get; init; }
    public DateTime? ProximaAccionFecha    { get; init; }
    /// <summary>Negativo = vencida hace N días · 0 = hoy · 1 = mañana.</summary>
    public int?      DiasParaAccion        { get; init; }
    public int?      HorasParaAccion       { get; init; }
    public string?   PrioridadAccion       { get; init; }
    public string?   PrioridadAccionCodigo { get; init; }
    /// <summary>en_seguimiento | sin_respuesta | requiere_ajuste | aceptada | rechazada</summary>
    public string    EstadoSeguimiento     { get; init; } = "";
    public string    EstadoPropuesta       { get; init; } = "";
    /// <summary>en_plazo | proximo | vencido | cumplido | cerrado</summary>
    public string    SlaEstado             { get; init; } = "";
    /// <summary>Porcentaje consumido del plazo de la próxima acción (barra SLA). null = cerrado.</summary>
    public int?      SlaPct                { get; init; }
    public DateTime? FechaAceptacion       { get; init; }
    public DateTime? FechaRechazo          { get; init; }
    public bool      TieneOc               { get; init; }
    public int       OcPorValidar          { get; init; }
}

public record ParametrosSeguimientoDto(int DiasSinRespuesta, int SlaHoras, int AlertaHoras, int MetaAceptadasMes);

public record BandejaSeguimientoDto(
    KpisSeguimientoDto              Kpis,
    List<ItemBandejaSeguimientoDto> Items,
    int                             Total,
    int                             Pagina,
    int                             PorPagina,
    List<OpcionFiltroDto>           Responsables,
    ParametrosSeguimientoDto        Parametros);

// ══════════════════════ HU-18 — Vista Detalle del Seguimiento ══════════════════════

/// <summary>Panel superior, datos de la oportunidad, próxima acción y permisos de los botones.</summary>
public record CabeceraDetalleSeguimientoDto
{
    public long      IdPropuesta           { get; init; }
    public string    Numero                { get; init; } = "";
    public int       Version               { get; init; }
    public long?     IdRequerimiento       { get; init; }
    public string?   NumeroRq              { get; init; }
    public long      IdCliente             { get; init; }
    public string    RazonSocial           { get; init; } = "";
    public string?   Ruc                   { get; init; }
    public long?     IdContacto            { get; init; }
    public string?   Contacto              { get; init; }
    public string?   CargoContacto         { get; init; }
    public string?   TelefonoContacto      { get; init; }
    public string?   CorreoContacto        { get; init; }
    public decimal   Total                 { get; init; }
    public int       IdMoneda              { get; init; }
    public string?   Moneda                { get; init; }
    public string?   MonedaSimbolo         { get; init; }
    public DateTime? FechaEnvio            { get; init; }
    public int       DiasTranscurridos     { get; init; }
    public int       DiasSinRespuesta      { get; init; }
    public long      IdResponsable         { get; init; }
    public string?   Responsable           { get; init; }
    public int       Interacciones         { get; init; }
    public DateTime? FechaUltimaInteraccion { get; init; }
    public string?   ResultadoUltimoCodigo { get; init; }
    public string?   ResultadoUltimo       { get; init; }
    // Próxima acción
    public string?   ProximaAccionCodigo   { get; init; }
    public string?   ProximaAccion         { get; init; }
    public string?   ProximaAccionDetalle  { get; init; }
    public DateTime? ProximaAccionFecha    { get; init; }
    public int?      DiasParaAccion        { get; init; }
    public int?      HorasParaAccion       { get; init; }
    /// <summary>SLA restante en minutos (negativo = vencido). Ej. 120 → "2h restantes".</summary>
    public int?      MinutosParaAccion     { get; init; }
    public int?      IdPrioridadAccion     { get; init; }
    public string?   PrioridadAccion       { get; init; }
    public string?   PrioridadAccionCodigo { get; init; }
    public long?     IdAsignado            { get; init; }
    public string?   Asignado              { get; init; }
    // Estado y SLA
    /// <summary>en_seguimiento | sin_respuesta | requiere_ajuste | aceptada | rechazada</summary>
    public string    EstadoSeguimiento     { get; init; } = "";
    public string    EstadoPropuesta       { get; init; } = "";
    /// <summary>en_plazo | proximo | vencido | cumplido | cerrado</summary>
    public string    SlaEstado             { get; init; } = "";
    public int?      SlaPct                { get; init; }
    public int       SlaHoras              { get; init; }
    public DateTime? FechaAceptacion       { get; init; }
    public DateTime? FechaRechazo          { get; init; }
    public bool      TieneOc               { get; init; }
    public int       OcPorValidar          { get; init; }
    // Botones
    public bool      PuedeRegistrarSeguimiento { get; init; }
    public bool      PuedeEjecutarAccion       { get; init; }
    public bool      PuedeRegistrarAceptacion  { get; init; }
    public bool      PuedeRegistrarRechazo     { get; init; }
    /// <summary>HU-20 — botón "Reprogramar".</summary>
    public bool      PuedeReprogramar          { get; init; }
    /// <summary>HU-20 — veces que se reprogramó la próxima acción.</summary>
    public int       Reprogramaciones          { get; init; }
    /// <summary>HU-21 — botón "Cerrar sin venta".</summary>
    public bool      PuedeCerrarSinVenta       { get; init; }
    /// <summary>HU-21 — el cierre sin venta permite reactivación futura (null si no está cerrado).</summary>
    public bool      PermiteReactivacion       { get; init; }
}

/// <summary>
/// Evento del timeline. Tipo: propuesta_creada | vb_solicitado | vb_aprobado | vb_devuelto | vb_rechazado |
/// vb_cancelado | enviada_cliente | seguimiento | cierre_aceptacion | cierre_rechazo | cierre_sin_venta |
/// accion_reprogramada (HU-20) | orden_compra.
/// </summary>
public record EventoTimelineSeguimientoDto(
    DateTime  Fecha,
    string    Tipo,
    string    Titulo,
    string?   Descripcion,
    int       Version,
    long?     IdUsuario,
    string?   Usuario,
    string?   CanalCodigo,
    string?   Canal,
    string?   ResultadoCodigo,
    long?     IdSeguimiento,
    int?      DuracionMinutos = null,
    string?   Asunto          = null,
    int       Adjuntos        = 0);

/// <summary>Acción programada. Estado: pendiente | vencida | realizada | reprogramada | cancelada.</summary>
public record ProximaAccionSeguimientoDto(
    long      IdSeguimiento,
    DateTime? Fecha,
    string?   TipoCodigo,
    string    Tipo,
    string?   Detalle,
    int?      IdPrioridad,
    string?   Prioridad,
    string?   PrioridadCodigo,
    long?     IdAsignado,
    string?   Asignado,
    string    Estado,
    DateTime? ProgramadaEn);

public record ContactoSeguimientoDto(
    long    IdContacto,
    string  Nombres,
    string? Cargo,
    string? Area,
    string? Correo,
    string? TelefonoMovil,
    string? TelefonoAnexo,
    string? Estado,
    bool    EsContactoPrincipal,
    bool    AutorizadoAprobarCotizaciones,
    bool    EsContactoPropuesta);

/// <summary>Tipo: propuesta_pdf (Url = endpoint del PDF de esa versión) | orden_compra (Url = archivo, puede ser null) |
/// adjunto_seguimiento (Url = endpoint de descarga, HU-19).</summary>
public record DocumentoSeguimientoDto(
    string    Tipo,
    string    Nombre,
    DateTime? Fecha,
    int       Version,
    string?   Url,
    string?   Estado);

public record DetalleSeguimientoDto(
    CabeceraDetalleSeguimientoDto       Cabecera,
    List<EventoTimelineSeguimientoDto>  Timeline,
    List<ProximaAccionSeguimientoDto>   ProximasAcciones,
    List<ContactoSeguimientoDto>        Contactos,
    List<DocumentoSeguimientoDto>       Documentos);

// ══════════════════════ HU-19 — Registro de acciones de seguimiento ══════════════════════

/// <summary>Próxima acción del toggle "Programar próxima acción". Fecha = fecha y hora programadas.</summary>
public record ProximaAccionEntradaDto
{
    public int?      IdTipoAccion  { get; init; }
    public DateTime? Fecha         { get; init; }
    public long?     IdResponsable { get; init; }
    public int?      IdPrioridad   { get; init; }
    public string?   Detalle       { get; init; }
}

/// <summary>
/// Registro general (modal "Registrar Seguimiento"). FechaInteraccion null = ahora.
/// EjecutaAccionPendiente = true cuando se abre desde "Ejecutar ahora": la acción pendiente queda realizada.
/// Sin próxima acción y sin EjecutaAccionPendiente, la acción pendiente anterior se mantiene.
/// </summary>
public record RegistrarSeguimientoDto
{
    public int?      IdCanal                { get; init; }
    public int?      IdResultado            { get; init; }
    public long?     IdContacto             { get; init; }
    public DateTime? FechaInteraccion       { get; init; }
    public string?   Notas                  { get; init; }
    public bool      ProgramarProximaAccion { get; init; }
    public ProximaAccionEntradaDto? ProximaAccion { get; init; }
    public bool      EjecutaAccionPendiente { get; init; }
}

/// <summary>Modal "Registrar Llamada": fecha y hora, duración, resultado y notas obligatorios.</summary>
public record RegistrarLlamadaDto
{
    public long?     IdContacto             { get; init; }
    public DateTime? FechaInteraccion       { get; init; }
    public int?      DuracionMinutos        { get; init; }
    public int?      IdResultado            { get; init; }
    public string?   Notas                  { get; init; }
    public bool      ProgramarProximaAccion { get; init; }
    public ProximaAccionEntradaDto? ProximaAccion { get; init; }
    public bool      EjecutaAccionPendiente { get; init; }
}

public record DestinatarioSeguimientoDto(string Correo, string? Nombre = null, long? IdContacto = null);

/// <summary>
/// Modal "Registrar Correo de Seguimiento". IdCorreo = borrador que se sigue editando (null = nuevo).
/// IdResultado null = "Correo enviado, pendiente respuesta". El correo sale desde el remitente del sistema
/// con el nombre del usuario y "responder a" su correo.
/// </summary>
public record CorreoSeguimientoDto
{
    public long?   IdCorreo                { get; init; }
    public int?    IdPlantilla             { get; init; }
    public List<DestinatarioSeguimientoDto> Para { get; init; } = [];
    public List<DestinatarioSeguimientoDto> Cc   { get; init; } = [];
    public string? Asunto                  { get; init; }
    public string? CuerpoHtml              { get; init; }
    public long?   IdContacto              { get; init; }
    public int?    IdResultado             { get; init; }
    public bool    ProgramarProximaAccion  { get; init; }
    public ProximaAccionEntradaDto? ProximaAccion { get; init; }
    public bool    EjecutaAccionPendiente  { get; init; }
}

/// <summary>Datos que el caso de uso envía al SP de registro.</summary>
public record ComandoRegistroSeguimiento(
    int?      IdCanal,
    string?   CanalCodigo,
    int?      IdResultado,
    string?   ResultadoCodigo,
    long?     IdContacto,
    DateTime? FechaInteraccion,
    int?      DuracionMinutos,
    string?   Notas,
    string?   Asunto,
    bool      Programar,
    ProximaAccionEntradaDto? ProximaAccion,
    bool      EjecutaAccion,
    long?     IdCorreo  = null,
    string?   Proveedor = null,
    string?   IdMensaje = null);

public record ComandoCorreoSeguimiento(
    long?   IdCorreo,
    int?    IdPlantilla,
    List<DestinatarioSeguimientoDto> Para,
    List<DestinatarioSeguimientoDto> Cc,
    string  Asunto,
    string  CuerpoHtml);

public record CorreoSeguimientoGuardadoDto(long IdCorreo, string Usuario, string? CorreoUsuario, string? CargoUsuario);

public record ResultadoRegistroSeguimientoDto(long IdSeguimiento, long? IdCorreo = null);

public record AdjuntoSeguimientoDto(long IdAdjunto, string NombreArchivo, long TamanoBytes, string Url);

public record RutaAdjuntoSeguimientoDto(string Ruta, string NombreArchivo, string TipoContenido);

// ── Preparación de los modales ────────────────────────────────────────────────

public record CabeceraRegistroSeguimientoDto
{
    public long      IdPropuesta              { get; init; }
    public string    Numero                   { get; init; } = "";
    public int       Version                  { get; init; }
    public long      IdCliente                { get; init; }
    public string    RazonSocial              { get; init; } = "";
    public string?   Referencia               { get; init; }
    public long?     IdContacto               { get; init; }
    public string?   Contacto                 { get; init; }
    public string?   TelefonoContacto         { get; init; }
    public string?   CorreoContacto           { get; init; }
    public long      IdUsuario                { get; init; }
    public string?   Usuario                  { get; init; }
    public string?   CorreoUsuario            { get; init; }
    public string?   CargoUsuario             { get; init; }
    /// <summary>Fecha y hora del servidor para prellenar "Fecha de registro" y el pie del modal.</summary>
    public DateTime? FechaServidor            { get; init; }
    public string    EstadoSeguimiento        { get; init; } = "";
    public string?   ProximaAccionCodigo      { get; init; }
    public string?   ProximaAccion            { get; init; }
    public DateTime? ProximaAccionFecha       { get; init; }
    /// <summary>Canal sugerido para "Ejecutar ahora" (LLAMADA, CORREO, REUNION, VISITA).</summary>
    public string?   CanalSugeridoCodigo      { get; init; }
    /// <summary>Plantilla sugerida (SEGUIMIENTO_INICIAL, RECORDATORIO, ENVIO_AJUSTES).</summary>
    public string?   PlantillaSugeridaCodigo  { get; init; }
}

public record OpcionSeguimientoDto(int Id, string Nombre, string? Codigo);

public record ContactoRegistroSeguimientoDto(
    long    IdContacto,
    string  Nombres,
    string? Cargo,
    string? Correo,
    string? TelefonoMovil,
    string? TelefonoAnexo,
    bool    EsContactoPropuesta,
    bool    EsContactoPrincipal);

public record ResponsableSeguimientoDto(long Id, string Nombre, string? Cargo, bool EsUsuarioActual);

/// <summary>Plantilla con las variables ya reemplazadas para esta propuesta.</summary>
public record PlantillaCorreoSeguimientoDto(int IdPlantilla, string Codigo, string Nombre, string Asunto, string CuerpoHtml);

/// <summary>Último borrador (o envío fallido) del usuario. Estado: borrador | error.</summary>
public record BorradorCorreoSeguimientoDto(
    long      IdCorreo,
    int?      IdPlantilla,
    List<DestinatarioSeguimientoDto> Para,
    List<DestinatarioSeguimientoDto> Cc,
    string    Asunto,
    string    CuerpoHtml,
    string    Estado,
    string?   Error,
    DateTime? Fecha);

public record PreparacionRegistroSeguimientoDto(
    CabeceraRegistroSeguimientoDto       Cabecera,
    List<OpcionSeguimientoDto>           TiposSeguimiento,
    List<OpcionSeguimientoDto>           Resultados,
    List<ContactoRegistroSeguimientoDto> Contactos,
    List<OpcionSeguimientoDto>           TiposTarea,
    List<OpcionSeguimientoDto>           Prioridades,
    List<ResponsableSeguimientoDto>      Responsables,
    List<PlantillaCorreoSeguimientoDto>  Plantillas,
    BorradorCorreoSeguimientoDto?        Borrador);

// ══════════════════════ HU-20 — Reprogramación de acciones ══════════════════════

/// <summary>Modal "Reprogramar Próxima Acción". Fecha = nueva fecha y hora. Detalle obligatorio (10 a 500).</summary>
public record ReprogramarAccionDto
{
    public int?      IdTipoAccion  { get; init; }
    public DateTime? Fecha         { get; init; }
    public int?      IdPrioridad   { get; init; }
    public long?     IdResponsable { get; init; }
    public int?      IdMotivo      { get; init; }
    public string?   Detalle       { get; init; }
}

/// <summary>
/// Acción actual. Origen: programada (registrada en un seguimiento o reprogramación) |
/// calculada (plazo por defecto del SLA, sin tipo ni prioridad).
/// </summary>
public record AccionActualSeguimientoDto
{
    public long      IdPropuesta          { get; init; }
    public string    Numero               { get; init; } = "";
    public int       Version              { get; init; }
    public long      IdCliente            { get; init; }
    public string    RazonSocial          { get; init; } = "";
    public string?   ProximaAccionCodigo  { get; init; }
    public string?   ProximaAccion        { get; init; }
    public int?      IdTipoAccion         { get; init; }
    public DateTime? FechaProgramada      { get; init; }
    public int?      IdPrioridad          { get; init; }
    public string?   Prioridad            { get; init; }
    public string?   PrioridadCodigo      { get; init; }
    public long?     IdResponsable        { get; init; }
    public string?   Responsable          { get; init; }
    public string    Origen               { get; init; } = "";
    public string    SlaEstado            { get; init; } = "";
    public string    EstadoSeguimiento    { get; init; } = "";
    public int       Reprogramaciones     { get; init; }
    public DateTime? FechaServidor        { get; init; }
}

public record ReprogramacionHistorialDto(
    long      IdReprogramacion,
    DateTime? Fecha,
    DateTime? FechaAnterior,
    string?   TipoAnterior,
    DateTime? FechaNueva,
    string?   TipoNuevo,
    string?   PrioridadNueva,
    string?   ResponsableNuevo,
    string?   Motivo,
    string?   MotivoCodigo,
    string?   Detalle,
    string?   Usuario);

public record PreparacionReprogramacionDto(
    AccionActualSeguimientoDto        AccionActual,
    List<OpcionSeguimientoDto>        TiposAccion,
    List<OpcionSeguimientoDto>        Prioridades,
    List<ResponsableSeguimientoDto>   Responsables,
    List<OpcionSeguimientoDto>        Motivos,
    List<ReprogramacionHistorialDto>  Historial);

public record ResultadoReprogramacionDto(long IdReprogramacion);

// ══════════════════════ HU-21 — Cierre del seguimiento ══════════════════════

/// <summary>Registrar Aceptación. Fecha null = ahora. La evidencia se sube luego a .../registros/{idSeguimiento}/adjuntos.</summary>
public record RegistrarAceptacionDto
{
    public int?      IdTipoAceptacion { get; init; }
    public long?     IdContacto       { get; init; }
    public DateTime? Fecha            { get; init; }
    public string?   Comentario       { get; init; }
}

/// <summary>Registrar Rechazo: motivo (MOTIVO_RECHAZO) y comentario de al menos 20 caracteres.</summary>
public record RegistrarRechazoDto
{
    public int?      IdMotivo   { get; init; }
    public DateTime? Fecha      { get; init; }
    public string?   Comentario { get; init; }
}

/// <summary>Cerrar sin Venta: motivo (MOTIVO_CIERRE_SIN_VENTA), detalle (mín. 20), reactivación y confirmación.</summary>
public record CerrarSinVentaDto
{
    public int?    IdMotivo             { get; init; }
    public string? Detalle              { get; init; }
    public bool    PermitirReactivacion { get; init; }
    public bool    ConfirmoCierre       { get; init; }
}

/// <summary>Datos que el caso de uso envía al SP de cierre. Tipo: aceptacion | rechazo | sin_venta.</summary>
public record ComandoCierreSeguimiento(
    string    Tipo,
    int?      IdTipoAceptacion,
    int?      IdMotivo,
    long?     IdContacto,
    DateTime? Fecha,
    string?   Comentario,
    bool      PermiteReactivacion,
    bool      Confirmado);

/// <summary>EstadoSeguimiento: aceptada | rechazada. SiguienteEtapa: ordenes_compra (aceptación) o null.</summary>
public record ResultadoCierreSeguimientoDto(long IdSeguimiento, string EstadoSeguimiento, string? SiguienteEtapa);

public record CabeceraCierreSeguimientoDto
{
    public long      IdPropuesta       { get; init; }
    public string    Numero            { get; init; } = "";
    public int       Version           { get; init; }
    public long      IdCliente         { get; init; }
    public string    RazonSocial       { get; init; } = "";
    public string?   Ruc               { get; init; }
    public long?     IdRequerimiento   { get; init; }
    public string?   NumeroRq          { get; init; }
    public decimal   Total             { get; init; }
    public int       IdMoneda          { get; init; }
    public string?   Moneda            { get; init; }
    public string?   MonedaSimbolo     { get; init; }
    public long      IdResponsable     { get; init; }
    public string?   Responsable       { get; init; }
    public long?     IdContacto        { get; init; }
    public string?   Contacto          { get; init; }
    public string?   CargoContacto     { get; init; }
    public string    EstadoSeguimiento { get; init; } = "";
    public int       DiasTranscurridos { get; init; }
    public DateTime? FechaServidor     { get; init; }
}

public record PreparacionCierreSeguimientoDto(
    CabeceraCierreSeguimientoDto         Cabecera,
    List<OpcionSeguimientoDto>           TiposAceptacion,
    List<OpcionSeguimientoDto>           MotivosRechazo,
    List<OpcionSeguimientoDto>           MotivosSinVenta,
    List<ContactoRegistroSeguimientoDto> Contactos);
