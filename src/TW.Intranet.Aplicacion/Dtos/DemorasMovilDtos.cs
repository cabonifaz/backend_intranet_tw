namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-05 — Registro de demoras en ruta ─────────────────────────────────────────

/// <summary>
/// Contexto de la pantalla "Registrar demora" de una OS del técnico. Las horas son de Lima.
///   EtaOriginal   = hora programada del servicio; EtaVigente = ETA original + las demoras de llegada ya registradas.
///   InicioPrevisto= inicio del trabajo previsto para las demoras de ingreso a planta (nunca antes de "ahora").
///   PuedeLlegada / PuedeIngreso = qué tipos se pueden registrar ahora (las reglas viven en SP_ObtenerDemorasMovil).
/// </summary>
public record ContextoDemorasMovilDto(
    long      IdOs,
    string    NumeroOs,
    string    EstadoOs,
    string?   Cliente,
    string?   Sede,
    DateTime? SalidaEn,
    int?      EnRutaMinutos,
    DateTime? LlegadaEn,
    int?      EnPlantaMinutos,
    DateTime? EtaOriginal,
    int       MinutosDemora,
    DateTime? EtaVigente,
    DateTime? InicioPrevisto,
    DateTime  Ahora,
    bool      PuedeLlegada,
    bool      PuedeIngreso,
    string?   MotivoNoRegistra,
    List<MotivoDemoraMovilDto>   Motivos,
    List<DemoraRegistradaMovilDto> Demoras)
{
    /// <summary>Hay al menos un tipo de demora que se puede registrar.</summary>
    public bool PuedeRegistrar => PuedeLlegada || PuedeIngreso;
}

/// <summary>Tipo de demora del catálogo MOTIVO_DEMORA_RUTA. Ambito: traslado | ingreso | ambos.</summary>
public record MotivoDemoraMovilDto(int IdMotivo, string Nombre, string? Codigo, string Ambito);

/// <summary>Una demora ya registrada. Tipo: llegada | ingreso.</summary>
public record DemoraRegistradaMovilDto(
    long      IdDemora,
    string    Tipo,
    string?   Motivo,
    int       DuracionMinutos,
    string?   Descripcion,
    DateTime? FechaRegistro,
    DateTime? EtaAnterior,
    DateTime? EtaRecalculada,
    bool      TieneFoto,
    decimal?  Latitud,
    decimal?  Longitud);

/// <summary>
/// Lo que el técnico envía al registrar una demora (la foto se recibe aparte).
/// CapturadoUtc = hora (UTC) en que el técnico la registró en el teléfono. Si no había conexión y la app la guardó para enviarla
/// después, el SP respeta esa hora (no futura, máx. 24 h); si no viene, vale la hora del servidor.
/// </summary>
public record NuevaDemoraMovilDto(
    string?  Tipo,
    int      IdMotivo,
    int      DuracionMinutos,
    string?  Descripcion,
    decimal? Latitud,
    decimal? Longitud,
    decimal? PrecisionMetros,
    DateTime? CapturadoUtc = null);

/// <summary>
/// Resultado del registro: las horas antes y después, y a cuántas personas de Operaciones se avisó.
/// Repetida = el envío ya estaba registrado (no se duplicó ni se avisó de nuevo). Diferida = se guardó sin conexión y llegó después.
/// </summary>
public record ResultadoDemoraMovilDto(
    long      IdDemora,
    string    Tipo,
    DateTime? EtaOriginal,
    DateTime? EtaAnterior,
    DateTime? EtaRecalculada,
    int       Notificados,
    bool      Repetida = false,
    bool      Diferida = false);
