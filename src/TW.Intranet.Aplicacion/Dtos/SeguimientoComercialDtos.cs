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
