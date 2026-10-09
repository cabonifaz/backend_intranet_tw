namespace TW.Intranet.Aplicacion.Dtos;

// ══════════════════════ HU-13 — Bandeja de Visto Bueno ══════════════════════

/// <summary>Filtros de la bandeja. Estado: pendiente | aprobado | devuelto | rechazado (vacío = todos).
/// Sla: en_plazo | proximo | vencido | cumplido | fuera_de_plazo. Dias: hacia atrás (0 = todo; los pendientes se ven siempre).</summary>
public record FiltrosBandejaVistoBuenoDto
{
    public long?   IdComercial { get; init; }
    public string? Estado      { get; init; }
    public int?    IdMoneda    { get; init; }
    public string? Sla         { get; init; }
    public int     Dias        { get; init; } = 30;
    public int     Pagina      { get; init; } = 1;
    public int     PorPagina   { get; init; } = 10;
}

public record KpisVistoBuenoDto(int Pendientes, int ProximosVencer, int Vencidos, int AprobadasHoy, int Devueltas);

public record ItemBandejaVistoBuenoDto
{
    public long      IdVb                 { get; init; }
    public long      IdPropuesta          { get; init; }
    public string    Numero               { get; init; } = "";
    public int       Version              { get; init; }
    public long?     IdRequerimiento      { get; init; }
    public string?   NumeroRq             { get; init; }
    public long      IdCliente            { get; init; }
    public string    RazonSocial          { get; init; } = "";
    public string?   Ruc                  { get; init; }
    public string?   Referencia           { get; init; }
    public decimal   Total                { get; init; }
    public int       IdMoneda             { get; init; }
    public string?   Moneda               { get; init; }
    public string?   MonedaSimbolo        { get; init; }
    public decimal   DescuentoPct         { get; init; }
    public long      IdComercial          { get; init; }
    public string    Comercial            { get; init; } = "";
    public long?     IdAprobador          { get; init; }
    /// <summary>Pendiente: quien debe aprobar ahora (jefe o su suplente vigente). Resuelto: quien resolvió.</summary>
    public string?   Aprobador            { get; init; }
    public bool      AprobadorEsSuplente  { get; init; }
    /// <summary>HU-16 — el VB fue reasignado a otro aprobador.</summary>
    public bool      Reasignado           { get; init; }
    /// <summary>pendiente | aprobado | devuelto | rechazado</summary>
    public string    EstadoVb             { get; init; } = "";
    public DateTime? FechaSolicitud       { get; init; }
    public DateTime? FechaRespuesta       { get; init; }
    public DateTime? VenceEn              { get; init; }
    public decimal   SlaHoras             { get; init; }
    public decimal   HorasTranscurridas   { get; init; }
    public decimal   HorasRestantes       { get; init; }
    /// <summary>en_plazo | proximo | vencido (pendientes) · cumplido | fuera_de_plazo (resueltos)</summary>
    public string    SlaEstado            { get; init; } = "";
    public bool      RequiereAprobacionEspecial { get; init; }
    public string?   ComentarioSolicitud  { get; init; }
    public string?   ComentarioRespuesta  { get; init; }
    public bool      PuedeResolver        { get; init; }
}

public record OpcionFiltroDto(long Id, string Nombre, string? Codigo = null);

public record PoliticasVistoBuenoDto(
    decimal DescuentoAprobacionEspecialPct,
    decimal MargenMinimoPct,
    decimal SlaHorasHabiles,
    int     JornadaInicio,
    int     JornadaFin,
    decimal ProximoVencerPct);

public record BandejaVistoBuenoDto(
    KpisVistoBuenoDto              Kpis,
    List<ItemBandejaVistoBuenoDto> Items,
    int                            Total,
    int                            Pagina,
    int                            PorPagina,
    List<OpcionFiltroDto>          Comerciales,
    List<OpcionFiltroDto>          Monedas,
    PoliticasVistoBuenoDto         Politicas);

/// <summary>Accion: aprobar | corregir | rechazar. Comentario obligatorio (mín. 10) para corregir y rechazar.</summary>
/// <summary>
/// HU-13 / HU-15 — Decisión sobre el VB. Accion: aprobar | corregir | rechazar.
///   aprobar  → ValidacionesConfirmadas (códigos de VALIDACION_APROBACION_VB), Comentario opcional.
///   rechazar → IdMotivoRechazo (MOTIVO_RECHAZO) y Comentario = justificación.
///   corregir → Areas (códigos de AREA_CORRECCION_PROPUESTA), Comentario = observaciones y FechaLimite.
/// </summary>
public record ResolverVistoBuenoDto(
    string        Accion,
    string?       Comentario,
    List<string>? ValidacionesConfirmadas = null,
    int?          IdMotivoRechazo         = null,
    List<string>? Areas                   = null,
    DateTime?     FechaLimite             = null);

/// <param name="IdCorreccion">Solo al solicitar corrección.</param>
public record ResultadoResolverVistoBuenoDto(
    long      IdPropuesta,
    string    Estado,
    string    EstadoVb,
    long?     IdCorreccion = null,
    DateTime? FechaLimite  = null);

// ══════════════════════ HU-15 — Modales de decisión ══════════════════════

/// <summary>GET /api/crm/propuestas/{id}/visto-bueno/decision</summary>
public record DecisionVistoBuenoDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    string    Estado,
    decimal   Total,
    string?   MonedaSimbolo,
    string?   MonedaCodigo,
    string?   Cliente,
    long?     IdComercial,
    string?   NombreComercial,
    long?     IdVistoBueno,
    bool      PuedeResolver,
    string?   MotivoBloqueo,
    DateTime? FechaLimiteSugerida,
    List<ValidacionRequeridaDto> ValidacionesRequeridas,
    List<OpcionCatalogoVbDto>    MotivosRechazo,
    List<AreaCorreccionDto>      AreasCorreccion);

public record ValidacionRequeridaDto(string Codigo, string Texto, bool Obligatoria);
public record OpcionCatalogoVbDto(int Id, string Nombre);
public record AreaCorreccionDto(string Codigo, string Etiqueta);

/// <summary>GET /api/crm/propuestas/{id}/correccion — última solicitud de corrección (null si nunca tuvo).</summary>
public record CorreccionPropuestaDto(
    long      IdCorreccion,
    string    Estado,
    string    Observaciones,
    DateTime? FechaLimite,
    bool      Vencida,
    DateTime? SolicitadoEn,
    string?   SolicitadoPor,
    long?     IdResponsable,
    string?   NombreResponsable,
    DateTime? AtendidaEn,
    List<AreaCorreccionDto> Areas);

// ══════════════════════ HU-14 — Validaciones previas ══════════════════════

/// <summary>Nivel: ok | alerta | error | no_disponible</summary>
public record ValidacionPreviaDto(string Codigo, string Etiqueta, string Nivel, string Detalle);

/// <summary>Cifras del margen solo si VeCostos (acción suministro_costo_ver).</summary>
public record ResumenEconomicoVbDto(
    int      IdMoneda,
    string?  MonedaSimbolo,
    decimal  Total,
    decimal? LineaCredito,
    decimal  CreditoConsumido,
    decimal? VentaConCosto,
    decimal? Costo,
    decimal? MargenPct,
    decimal  MargenMinimoPct,
    int      Items,
    int      ItemsSinCosto,
    decimal  DescuentoPct,
    bool     VeCostos);

public record ValidacionesVistoBuenoDto(
    List<ValidacionPreviaDto> Validaciones,
    ResumenEconomicoVbDto     Resumen,
    /// <summary>BAJO | MODERADO | ALTO (peor nivel de las validaciones).</summary>
    string                    RiesgoFinanciero);

// ══════════════════════ HU-14 — Comparar versiones ══════════════════════

public record CabeceraVersionDto
{
    public long      IdPropuesta        { get; init; }
    public string    Numero             { get; init; } = "";
    public int       Version            { get; init; }
    public string    Estado             { get; init; } = "";
    public DateTime? FechaEmision       { get; init; }
    public string?   Referencia         { get; init; }
    public string?   TipoServicio       { get; init; }
    public string?   Cliente            { get; init; }
    public int       IdMoneda           { get; init; }
    public string?   Moneda             { get; init; }
    public string?   MonedaSimbolo      { get; init; }
    public decimal   Subtotal           { get; init; }
    public decimal   DescuentoMonto     { get; init; }
    public decimal   DescuentoPct       { get; init; }
    public decimal   IgvPct             { get; init; }
    public decimal   IgvMonto           { get; init; }
    public decimal   Total              { get; init; }
    public bool      AplicaIgv          { get; init; }
    public int?      PlazoEntregaDias   { get; init; }
    public int?      VigenciaDias       { get; init; }
    public string?   CondicionPago      { get; init; }
    public string?   FormaPago          { get; init; }
    public string?   DescripcionCambios { get; init; }
    public string?   MotivoNuevaVersion { get; init; }
}

/// <summary>Estado: agregado | modificado | eliminado | igual (colores del front: verde, ámbar, rojo).</summary>
public record DiferenciaItemDto(
    string   Estado,
    string   Seccion,
    string   Descripcion,
    decimal? CantidadBase,
    decimal? CantidadDestino,
    decimal? PrecioUnitarioBase,
    decimal? PrecioUnitarioDestino,
    decimal? SubtotalBase,
    decimal? SubtotalDestino,
    List<string> CamposModificados);

public record DiferenciaCampoDto(string Campo, string Etiqueta, string? ValorBase, string? ValorDestino, string Estado);

public record DiferenciaElementoDto(string Estado, string Descripcion, string? Detalle = null);

public record ResumenComparacionDto(
    decimal DiferenciaTotal,
    decimal DiferenciaPct,
    int     ItemsBase,
    int     ItemsDestino,
    int     ItemsAgregados,
    int     ItemsModificados,
    int     ItemsEliminados,
    /// <summary>BAJO | MODERADO | ALTO (de la versión destino).</summary>
    string  RiesgoFinanciero,
    List<string> MotivosRiesgo);

public record VersionDisponibleDto(long IdPropuesta, int Version, string Estado, DateTime? FechaEmision);

public record ComparacionVersionesDto(
    CabeceraVersionDto                Base,
    CabeceraVersionDto                Destino,
    ResumenComparacionDto             Resumen,
    List<DiferenciaCampoDto>          Financiero,
    List<DiferenciaItemDto>           Items,
    List<DiferenciaCampoDto>          Condiciones,
    List<DiferenciaElementoDto>       Equipos,
    List<DiferenciaElementoDto>       Textos,
    List<ValidacionPreviaDto>         ValidacionesDestino,
    List<VersionDisponibleDto>        Versiones);

/// <summary>Datos crudos de dos versiones (uso interno, los entrega el repositorio).</summary>
public record DatosComparacionDto(
    CabeceraVersionDto Base,
    CabeceraVersionDto Destino,
    List<ItemVersionDto> Items,
    List<FormaPagoVersionDto> FormasPago,
    List<EquipoVersionDto> Equipos,
    List<TextoVersionDto> Textos,
    List<VersionDisponibleDto> Versiones);

public record ItemVersionDto(string Rol, long? IdCatalogoItem, string Seccion, string Descripcion,
                             decimal Cantidad, decimal PrecioUnitario, decimal Descuento, decimal Subtotal,
                             string? Alcance, string? PuntosCalibracion, decimal? Frecuencia);
public record FormaPagoVersionDto(string Rol, decimal Porcentaje, string Condicion);
public record EquipoVersionDto(string Rol, long? IdEquipo, string? NumSerie, string? CodigoTw, string? Tipo, string? Marca, string? Modelo);
public record TextoVersionDto(string Rol, string Seccion, string Texto);

// ══════════════════════ HU-14 — Precio de costo ══════════════════════

public record CostoSuministroDto(
    long      IdSuministro,
    decimal?  PrecioCosto,
    int       IdMoneda,
    string?   Moneda,
    decimal?  PrecioNivelEstandar,
    decimal?  MargenEstandarPct,
    DateTime? CostoActualizadoEn,
    string?   CostoActualizadoPor);

public record GuardarCostoSuministroDto(decimal? PrecioCosto);

// ══════════════════════ HU-16 — Reasignación de aprobador ══════════════════════

/// <summary>GET /api/crm/propuestas/{id}/visto-bueno/reasignacion</summary>
public record ReasignacionVistoBuenoDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    long      IdVistoBueno,
    long?     IdAprobador,
    string?   NombreAprobador,
    string?   CargoAprobador,
    DateTime? FechaAsignacion,
    bool      Reasignado,
    DateTime? FechaSolicitud,
    int       SlaHoras,
    decimal   HorasTranscurridas,
    decimal   HorasRestantes,
    DateTime? VenceEn,
    long?     IdComercial,
    string?   NombreComercial,
    bool      PuedeReasignar,
    string?   MotivoBloqueo,
    List<OpcionCatalogoVbDto> Motivos);

/// <summary>GET /api/crm/propuestas/{id}/visto-bueno/candidatos?buscar=</summary>
public record CandidatoAprobadorDto(long IdUsuario, string Nombre, string? Cargo, string? Area, string? RolSistema, string? Correo);

/// <summary>POST /api/crm/propuestas/{id}/visto-bueno/reasignar</summary>
public record ReasignarVistoBuenoDto(
    long    IdNuevoAprobador,
    int?    IdMotivo,
    string? Comentario,
    bool    ReiniciarSla = false);

public record ResultadoReasignacionVbDto(
    long      IdPropuesta,
    long      IdVistoBueno,
    long      IdAprobador,
    string    NombreAprobador,
    DateTime? FechaSolicitud,
    DateTime? VenceEn,
    bool      SlaReiniciado);
