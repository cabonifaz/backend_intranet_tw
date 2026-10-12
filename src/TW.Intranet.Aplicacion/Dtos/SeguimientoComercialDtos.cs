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
}

/// <summary>
/// Evento del timeline. Tipo: propuesta_creada | vb_solicitado | vb_aprobado | vb_devuelto | vb_rechazado |
/// vb_cancelado | enviada_cliente | seguimiento | cierre_aceptacion | cierre_rechazo | cierre_sin_venta | orden_compra.
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
    long?     IdSeguimiento);

/// <summary>Acción programada. Estado: pendiente | vencida | realizada | cancelada.</summary>
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

/// <summary>Tipo: propuesta_pdf (Url = endpoint del PDF de esa versión) | orden_compra (Url = archivo, puede ser null).</summary>
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
