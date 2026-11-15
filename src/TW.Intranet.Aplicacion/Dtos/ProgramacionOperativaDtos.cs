namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-35 Bandeja de Programación Operativa (Sprint 5) ───────────────────────

/// <summary>Filtros de las listas Pendientes y Programados (query string).</summary>
public class FiltrosProgramacionDto
{
    /// <summary>Pendientes: todos (defecto), pendiente_programar, pendiente_conf_cliente, pendiente_reprogramacion o pendiente_ssoma.</summary>
    public string?   SubEstado { get; set; }
    /// <summary>Programados: todos (defecto), hoy, esta_semana, proxima_semana o personalizado (usa FechaDesde / FechaHasta).</summary>
    public string?   Rango     { get; set; }
    public DateTime? FechaDesde { get; set; }
    public DateTime? FechaHasta { get; set; }
    /// <summary>todos (defecto), OS u OM.</summary>
    public string?   Tipo      { get; set; }
    public long?     IdCliente { get; set; }
    /// <summary>Área del requerimiento (catálogo 64).</summary>
    public int?      IdArea    { get; set; }
    /// <summary>Técnico asignado (como principal o como apoyo).</summary>
    public long?     IdTecnico { get; set; }
    /// <summary>Sede / planta del cliente.</summary>
    public long?     IdSede    { get; set; }
    /// <summary>Zona: región de la sede del cliente (texto de las opciones Zonas de la lista).</summary>
    public string?   Zona      { get; set; }
    /// <summary>N° OS/OM, N° de propuesta, cliente, RUC o técnico.</summary>
    public string?   Busqueda  { get; set; }
    public int       Pagina    { get; set; } = 1;
    public int       PorPagina { get; set; } = 10;
}

/// <summary>
/// Tarjetas KPI de la bandeja (panorama global, sin filtros). ServiciosHoy incluye los que están en curso y los ya
/// finalizados hoy; TecnicosDisponibles = de la plantilla y sin servicio pendiente hoy.
/// </summary>
public record TarjetasProgramacionDto(
    int ServiciosHoy,
    int EnEjecucionHoy,
    int PendientesProgramar,
    int PendientesConfCliente,
    int PendientesReprogramacion,
    int PendientesSsoma,
    int TotalPendientes,
    int Programados,
    int ProgramadosSemana,
    int ConConflicto,
    int TecnicosDisponibles,
    int PlantillaTecnicos,
    int FinalizadosHoy = 0);

/// <summary>
/// Bloque del calendario semanal: un servicio de una persona asignada. Rol: principal o apoyo (una orden con personal de
/// apoyo aparece en la fila de cada técnico). SubEstado colorea el bloque: pendiente_conf_cliente, pendiente_reprogramacion,
/// pendiente_ssoma, programado, en_curso o finalizado.
/// </summary>
public record ServicioCalendarioDto(
    long     IdOs,
    string   Tipo,
    string   Numero,
    string   Estado,
    string   SubEstado,
    long     IdTecnico,
    string?  Tecnico,
    string   Rol,
    string?  TecnicoPrincipal,
    string?  Fecha,
    string?  HoraInicio,
    string?  HoraFin,
    decimal? Horas,
    string?  Cliente,
    string?  Sede,
    string?  TipoServicio,
    bool     EnConflicto,
    bool     ConfirmadoCliente,
    /// <summary>Programación activa de la orden (abre el modal detalle desde la matriz de carga).</summary>
    long?    IdProgramacion = null);

/// <summary>Carga de un técnico en un día. Nivel: libre, baja, optimo, alta o sobrecarga.</summary>
public record CargaDiaDto(string Fecha, decimal Horas, string Nivel, bool Conflicto, int Servicios);

/// <summary>
/// Fila de la matriz "Carga semanal del equipo" (cuenta al técnico como principal y como apoyo). Tipo de recurso: tecnico
/// o metrologo. Nivel semanal: libre, baja, optimo, alta o sobrecarga.
/// </summary>
public record CargaTecnicoDto(
    long                  IdUsuario,
    string                Nombre,
    string?               Cargo,
    string                TipoRecurso,
    string?               SedeOperativa,
    IReadOnlyList<CargaDiaDto> Dias,
    decimal               TotalHoras,
    int                   UtilizacionPct,
    string                Nivel);

/// <summary>Alerta operativa. Tipo: conflicto, reprogramacion o ssoma. Severidad: critica o advertencia.</summary>
public record AlertaProgramacionDto(
    string  Tipo,
    string  Severidad,
    string  Titulo,
    string  Detalle,
    long?   IdUsuario,
    long?   IdOs,
    long?   IdOs2,
    string? Fecha,
    int     Cantidad);

/// <summary>Tab "Vista Principal".</summary>
public record ResumenProgramacionDto(
    string                          InicioSemana,
    string                          FinSemana,
    decimal                         CapacidadSemanalHoras,
    TarjetasProgramacionDto         Tarjetas,
    IReadOnlyList<ServicioCalendarioDto> Calendario,
    IReadOnlyList<CargaTecnicoDto>  Carga,
    IReadOnlyList<AlertaProgramacionDto> Alertas,
    /// <summary>Horas de la jornada de un técnico (parámetro HORAS_JORNADA).</summary>
    decimal                         CapacidadDiariaHoras = 8);

/// <summary>Fila de las listas Pendientes y Programados.</summary>
public class ItemProgramacionDto
{
    public long      IdOs                    { get; init; }
    public string    Tipo                    { get; init; } = "OS";
    public string    Numero                  { get; init; } = "";
    public string    Estado                  { get; init; } = "";
    public string    EstadoLabel             { get; init; } = "";
    /// <summary>pendiente_programar, pendiente_conf_cliente, pendiente_reprogramacion, pendiente_ssoma o programado.</summary>
    public string    SubEstado               { get; init; } = "";
    public string    SubEstadoLabel          { get; init; } = "";
    public long?     IdExpediente            { get; init; }
    public long?     IdCliente               { get; init; }
    public string?   RazonSocial             { get; init; }
    public string?   Ruc                     { get; init; }
    public long?     IdSede                  { get; init; }
    public string?   Sede                    { get; init; }
    /// <summary>Región de la sede del cliente.</summary>
    public string?   Zona                    { get; init; }
    public long?     IdPropuesta             { get; init; }
    public string?   NumeroPropuesta         { get; init; }
    public int?      VersionPropuesta        { get; init; }
    public string?   NumeroRequerimiento     { get; init; }
    public int?      IdArea                  { get; init; }
    public string?   Area                    { get; init; }
    public long?     IdTecnico               { get; init; }
    public string?   Tecnico                 { get; init; }
    /// <summary>Nombres del personal de apoyo, separados por coma.</summary>
    public string?   TecnicosApoyo           { get; init; }
    /// <summary>Personas asignadas (principal + apoyo).</summary>
    public int       NumeroTecnicos          { get; init; }
    public int?      IdTipoServicio          { get; init; }
    public string?   TipoServicio            { get; init; }
    /// <summary>Qué validación SSOMA bloquea la orden (solo órdenes programadas; null = ninguna).</summary>
    public string?   SsomaMotivo             { get; init; }
    /// <summary>Código de la programación vigente (PRG-AAAA-NNNN); null si la OS aún no se programó.</summary>
    public long?     IdProgramacion          { get; init; }
    public string?   CodigoProgramacion      { get; init; }
    public string?   FechaEjecucion          { get; init; }
    public string?   HoraInicio              { get; init; }
    public string?   HoraFin                 { get; init; }
    public decimal?  Horas                   { get; init; }
    /// <summary>Rango tentativo que fijó Comercial al emitir la orden.</summary>
    public string?   FechaProgramadaDesde    { get; init; }
    public string?   FechaProgramadaHasta    { get; init; }
    public bool      ConfirmacionCliente     { get; init; }
    public DateTime? FechaConfirmacionCliente { get; init; }
    public bool      EnConflicto             { get; init; }
    public long?     IdReprogramacionPendiente { get; init; }
    public int       DiasEnEspera            { get; init; }
    public decimal   ViaticoMonto            { get; init; }
    /// <summary>Monto asignado que aún no deposita Contabilidad (pendiente u observado).</summary>
    public decimal   ViaticoPendiente        { get; init; }
    /// <summary>Símbolo de la moneda de los viáticos (S/ por defecto).</summary>
    public string    ViaticoMoneda           { get; init; } = "S/";
    /// <summary>sin_asignar, pendiente_deposito o depositado.</summary>
    public string    ViaticoEstado           { get; init; } = "sin_asignar";
    // Acciones disponibles según el estado y el rol. Programar: HU-36. Reprogramar / solicitar / resolver: HU-38.
    // Cancelar: anulación de la OS/OM (POST api/crm/ordenes-servicio/{idOs}/anular, permiso os_anular).
    // Ver detalle: GET api/crm/ordenes-servicio/{idOs}.
    public bool      PuedeProgramar                { get; init; }
    public bool      PuedeReprogramar              { get; init; }
    public bool      PuedeSolicitarReprogramacion  { get; init; }
    public bool      PuedeResolverReprogramacion   { get; init; }
    public bool      PuedeCancelar                 { get; init; }
    /// <summary>Puede abrir el detalle de la OS/OM (permiso de consulta de órdenes: Comercial u Operaciones).</summary>
    public bool      PuedeVerDetalle               { get; init; }
}

/// <summary>Cantidad de pendientes por sub-estado con los demás filtros aplicados (chips del filtro Sub-estado).</summary>
public record ConteoSubEstadosDto(int PendienteProgramar, int PendienteConfCliente, int PendienteReprogramacion, int PendienteSsoma)
{
    public int Total => PendienteProgramar + PendienteConfCliente + PendienteReprogramacion + PendienteSsoma;
}

/// <summary>
/// Lista paginada (Pendientes o Programados) con las opciones de los filtros (solo datos que existen). En Zonas, Nombre y
/// Codigo traen la región (Id = 0). ConteoSubEstados solo viene en Pendientes.
/// </summary>
public record ListaProgramacionDto(
    IReadOnlyList<ItemProgramacionDto> Items,
    int                                Total,
    int                                Pagina,
    int                                PorPagina,
    IReadOnlyList<OpcionFiltroDto>     Clientes,
    IReadOnlyList<OpcionFiltroDto>     Areas,
    IReadOnlyList<OpcionFiltroDto>     Tecnicos,
    IReadOnlyList<OpcionFiltroDto>     Sedes,
    IReadOnlyList<OpcionFiltroDto>?    Zonas = null,
    ConteoSubEstadosDto?               ConteoSubEstados = null);
