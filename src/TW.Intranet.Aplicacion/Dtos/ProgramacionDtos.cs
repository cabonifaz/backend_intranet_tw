namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-36 Programación de OS y asignación de recursos (Sprint 5) ─────────────

/// <summary>
/// Ficha "Programar Servicio": datos heredados de la OS/OM, equipos a intervenir, requisitos SSOMA del cliente/zona y
/// conceptos del servicio.
/// </summary>
public record FichaProgramacionDto(
    OrdenParaProgramarDto                 Orden,
    IReadOnlyList<EquipoProgramacionDto>  Equipos,
    IReadOnlyList<RequisitoSsomaProgramacionDto> RequisitosSsoma,
    IReadOnlyList<ConceptoProgramacionDto> Conceptos);

/// <summary>Concepto del servicio heredado de la OS.</summary>
public record ConceptoProgramacionDto(long IdOsConcepto, string? Codigo, string Descripcion, string? Alcance, int Orden);

/// <summary>Datos de la OS/OM que hereda la programación (no editables).</summary>
public class OrdenParaProgramarDto
{
    public long      IdOs                      { get; init; }
    public string    Tipo                      { get; init; } = "OS";
    public string    Numero                    { get; init; } = "";
    public string    Estado                    { get; init; } = "";
    public long?     IdExpediente              { get; init; }
    public string?   NumeroExpediente          { get; init; }
    public long?     IdCliente                 { get; init; }
    public string?   RazonSocial               { get; init; }
    public string?   Ruc                       { get; init; }
    public long?     IdSede                    { get; init; }
    public string?   Sede                      { get; init; }
    public string?   Ubicacion                 { get; init; }
    public long?     IdPropuesta               { get; init; }
    public string?   NumeroPropuesta           { get; init; }
    public int?      VersionPropuesta          { get; init; }
    public int?      IdTipoServicio            { get; init; }
    /// <summary>Ej.: Mantenimiento Preventivo (catálogo 3).</summary>
    public string?   TipoServicio              { get; init; }
    public string?   NumeroRequerimiento       { get; init; }
    /// <summary>Área del requerimiento (catálogo 64).</summary>
    public int?      IdArea                    { get; init; }
    public string?   Area                      { get; init; }
    /// <summary>Rango tentativo que fijó Comercial al emitir la orden.</summary>
    public string?   FechaProgramadaDesde      { get; init; }
    public string?   FechaProgramadaHasta      { get; init; }
    public int       NumeroEquipos             { get; init; }
    public int       NumeroConceptos           { get; init; }
    public long?     IdProgramacionActiva      { get; init; }
    public string?   CodigoProgramacionActiva  { get; init; }
    /// <summary>Solo una orden EMITIDA sin programación activa se puede programar.</summary>
    public bool      PuedeProgramar            { get; init; }
    public string?   MotivoNoProgramable       { get; init; }
}

public record EquipoProgramacionDto(
    long    IdOsEquipo,
    long    IdEquipo,
    string? CodigoTw,
    string? Marca,
    string? Modelo,
    string? NumeroSerie,
    string? Ubicacion,
    string? AlcanceMaximo,
    int     Orden);

/// <summary>
/// Requisito SSOMA del cliente / sede / tipo de servicio. AplicaA: ambos, tecnico u otro valor del catálogo 48.
/// DocumentoEquivalente: tipo de documento del técnico que lo acredita (null = no se puede verificar automáticamente).
/// Se verifica contra cada técnico en el buscador y al crear la programación.
/// </summary>
public record RequisitoSsomaProgramacionDto(
    long Id, int IdRequisito, string Requisito, bool EsObligatorio, bool BloqueaServicio, string? Sede,
    string AplicaA, string? DocumentoEquivalente);

/// <summary>Filtros del buscador de técnicos (query string). La hora va como HH:mm.</summary>
public class FiltrosTecnicosProgramacionDto
{
    public DateTime? Fecha                { get; set; }
    public string?   HoraInicio           { get; set; }
    public string?   HoraFin              { get; set; }
    /// <summary>Solo técnicos sin otro servicio que se cruce con el horario (requiere fecha y horas).</summary>
    public bool      SoloDisponibles      { get; set; }
    /// <summary>Solo técnicos con SSOMA conforme.</summary>
    public bool      SoloSsomaConforme    { get; set; }
    /// <summary>Nombre o cargo.</summary>
    public string?   Busqueda             { get; set; }
    /// <summary>Código de SEDE_OPERATIVA_TW (lima_central, arequipa).</summary>
    public string?   SedeOperativa        { get; set; }
    /// <summary>Pestaña del modal "Asignar Recurso": tecnico, metrologo o externo (vacío = todos).</summary>
    public string?   TipoRecurso          { get; set; }
}

/// <summary>Filtros ya validados que recibe el repositorio.</summary>
public record FiltroTecnicosProgramacion(
    DateTime? Fecha, TimeSpan? HoraInicio, TimeSpan? HoraFin,
    bool SoloDisponibles, bool SoloSsomaConforme, string? Busqueda, string? SedeOperativa, string? TipoRecurso = null);

/// <summary>
/// Requisito SSOMA de un técnico: los que pide el cliente/zona (Requerido) y sus demás documentos (último de cada tipo).
/// Estado: estado del documento (null si no tiene). Situación: conforme, por_vencer, bloqueado, sin_documento o sin_verificar.
/// Bloquea: si su situación bloqueada impide programar.
/// </summary>
public record DocumentoSsomaTecnicoDto(
    string Requisito, string? Estado, string? FechaVencimiento, string Situacion, bool Requerido, bool Bloquea);

/// <summary>
/// Técnico del buscador y del panel lateral "Detalle de recurso".
/// TipoRecurso: tecnico o metrologo. Disponibilidad: disponible, ocupado o sin_horario.
/// SSOMA: conforme, por_vencer, incompleto (le falta un documento que pide el cliente; no bloquea), pendiente (falta un
/// documento exigido; bloquea) o bloqueado. Experiencia con el cliente: alta, media o sin_experiencia.
/// </summary>
public record TecnicoProgramacionDto(
    long     IdUsuario,
    string   Nombre,
    string?  Cargo,
    string?  Area,
    string   TipoRecurso,
    string?  SedeOperativa,
    string?  SedeOperativaNombre,
    string   Disponibilidad,
    string?  ConflictoOs,
    string?  ConflictoDesde,
    string?  ConflictoHasta,
    int      ServiciosDia,
    decimal  HorasDia,
    int      ServiciosMaxDia,
    int      CupoLibre,
    decimal  HorasLibres,
    string   SsomaEstado,
    string?  SsomaMotivo,
    string?  SsomaFaltantes,
    int      SsomaRequeridos,
    int      SsomaCumplidos,
    int      ServiciosCliente,
    string   ExperienciaCliente,
    decimal? ScorecardPct,
    string?  ScorecardNivel,
    int?     ScorecardServicios,
    IReadOnlyList<DocumentoSsomaTecnicoDto> DocumentosSsoma);

/// <summary>Contadores de las pestañas del modal "Asignar Recurso" (Proveedor externo aún no tiene registro: siempre 0).</summary>
public record ContadoresRecursoDto(int Tecnicos, int Metrologos, int Externos);

public record BusquedaTecnicosDto(IReadOnlyList<TecnicoProgramacionDto> Tecnicos, int Total, ContadoresRecursoDto? Contadores = null);

/// <summary>Cuerpo de POST /api/operaciones/programacion. Las horas van como HH:mm.</summary>
public class CrearProgramacionDto
{
    public long       IdOs                 { get; set; }
    public DateTime?  FechaEjecucion       { get; set; }
    public string?    HoraInicio           { get; set; }
    public string?    HoraFin              { get; set; }
    public long       IdTecnicoPrincipal   { get; set; }
    /// <summary>Técnicos de apoyo (hasta 9).</summary>
    public List<long>? IdsTecnicosApoyo    { get; set; }
    /// <summary>Equipos de la OS confirmados para esta programación.</summary>
    public List<long>? IdsEquipos          { get; set; }
    public string?    Observaciones        { get; set; }
}

/// <summary>Programación ya validada que recibe el repositorio.</summary>
public record NuevaProgramacion(
    long IdOs, DateTime Fecha, TimeSpan HoraInicio, TimeSpan HoraFin, long IdTecnicoPrincipal,
    IReadOnlyList<long> IdsApoyo, IReadOnlyList<long> IdsEquipos, string? Observaciones);

public record ProgramacionCreadaDto(
    long    IdProgramacion,
    string  Codigo,
    long    IdOs,
    string  NumeroOs,
    string  Estado,
    string? FechaEjecucion,
    string? HoraInicio,
    string? HoraFin,
    IReadOnlyList<string> Advertencias);

/// <summary>Cuerpo de POST /api/operaciones/programacion/ordenes/{idOs}/derivar-ssoma.</summary>
public class DerivarSsomaDto
{
    /// <summary>Fecha del servicio con la que se evalúan los vencimientos (vacío = la de la orden o hoy).</summary>
    public DateTime?   Fecha        { get; set; }
    /// <summary>Técnicos evaluados en la ficha (de 1 a 10).</summary>
    public List<long>? IdsTecnicos  { get; set; }
    /// <summary>Nota opcional para SSOMA (hasta 500 caracteres).</summary>
    public string?     Comentario   { get; set; }
}

/// <summary>Derivación ya validada que recibe el repositorio.</summary>
public record NuevaDerivacionSsoma(long IdOs, DateTime? Fecha, IReadOnlyList<long> IdsTecnicos, string? Comentario);

/// <summary>Pendiente SSOMA derivado. Situación: bloqueado, por_vencer, sin_documento o sin_verificar.</summary>
public record PendienteSsomaDerivadoDto(long IdUsuario, string Tecnico, string Requisito, string Situacion, string? FechaVencimiento);

public record DerivacionSsomaDto(int Notificados, int TecnicosConPendientes, IReadOnlyList<PendienteSsomaDerivadoDto> Pendientes);
