namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-51 Bandeja de Seguimiento Operativo (Sprint 5) ─────────────────────────────────────────────────────────────
// Rol Asistente de Seguimiento: bandeja OBSERVACIONAL (ver y llamar al técnico por teléfono). Estos DTOs solo se leen.

/// <summary>Filtros globales de la bandeja (query string). Todos opcionales; el caso de uso los valida con listas cerradas y largos máximos.</summary>
public class ConsultaSeguimientoDto
{
    public long?   IdTecnico { get; set; }
    public long?   IdCliente { get; set; }
    public string? Estado    { get; set; }
    public string? Zona      { get; set; }
    public string? Busqueda  { get; set; }
    /// <summary>Solo pestaña Servicios en Campo: en_curso, finalizados o sin_iniciar.</summary>
    public string? Rango     { get; set; }
    public int?    Pagina    { get; set; }
    public int?    Tamano    { get; set; }
    /// <summary>Solo pestaña Incidencias del Día: código del catálogo (ej. TRAFICO) e impacto (retrasa o detiene).</summary>
    public string? Tipo      { get; set; }
    public string? Impacto   { get; set; }
}

/// <summary>Filtros ya validados y limpios (los únicos valores que llegan al SP).</summary>
public record ConsultaSeguimientoNormalizada(
    long? IdTecnico, long? IdCliente, string? Estado, string? Zona, string? Busqueda, string? Rango, int Pagina, int Tamano, string? Tipo, string? Impacto);

public record KpisBandejaSeguimientoDto(
    int Programados, int TecnicosEnRuta, int EnPlanta, int EnEjecucion, int ConDemoraIncidente, int Finalizados, int SinSalir,
    int ServiciosFiltrados, int TecnicosActivos, int IncidenciasDelDia, string Actualizado, int RefrescoSegundos);

public record PinMapaDto(
    long IdUsuario, string Tecnico, string Iniciales, string Estado, decimal? Latitud, decimal? Longitud, string Direccion,
    int? MinutosUbicacion, long? IdOs, string? NumeroOs, string? Cliente);

public record AlertaSeguimientoDto(
    string Clave, string Tipo, string Severidad, string Titulo, string Detalle, int Minutos, bool Nueva,
    long IdUsuario, string Tecnico, long IdOs, string NumeroOs);

public record TotalesAlertasDto(int Total, int Nuevas, int Criticas);

public record HitoEsperadoDto(long IdOs, string NumeroOs, string Tipo, string Hora, string Texto, string Detalle, bool Atrasado, long? IdTecnico);

public record ResumenHitosDto(bool TodosOcurrieron, int Pendientes);

/// <summary>KPIs superiores + pestaña 1 Vista Principal (mapa operativo, alertas críticas, próximos hitos esperados).</summary>
public record ResumenSeguimientoDto(
    KpisBandejaSeguimientoDto Kpis, IReadOnlyList<PinMapaDto> Pines, IReadOnlyList<AlertaSeguimientoDto> Alertas, TotalesAlertasDto TotalesAlertas,
    IReadOnlyList<HitoEsperadoDto> Hitos, ResumenHitosDto ResumenHitos);

public record ServicioSeguimientoDto(
    long IdOs, string Numero, string Tipo, string? Propuesta, string Cliente, string? Ruc, long? IdTecnico, string? Tecnico, string? Iniciales,
    string Estado, string? Zona, string? HoraInicio, string? UltimaUbicacion, int? MinutosUbicacion, int Equipos, int Ejecutados, int AvancePct);

/// <summary>Pestaña 2 Servicios en Campo.</summary>
public record ServiciosSeguimientoDto(
    int Total, int Pagina, int Tamano, int TotalPaginas, string? Actualizado, IReadOnlyList<ServicioSeguimientoDto> Filas);

public record ServicioDeTecnicoDto(
    long IdOs, string Numero, string Cliente, string Estado, string? HoraInicio, string? HoraFin, string Rol, int Equipos, int Ejecutados);

public record TecnicoSeguimientoDto(
    long IdUsuario, string Tecnico, string Iniciales, string? Cargo, string? Zona, string Estado, string? Ssoma, int Servicios, int Completados, int EnCurso,
    string? SalidaReal, string? SalidaProgramada, int? DiferenciaSalidaMin, string? UltimaUbicacion, int? MinutosUbicacion,
    IReadOnlyList<ServicioDeTecnicoDto> ServiciosDelDia);

/// <summary>Pestaña 3 Técnicos Activos.</summary>
public record TecnicosSeguimientoDto(int Total, int AdicionalesSinIniciar, string? Actualizado, IReadOnlyList<TecnicoSeguimientoDto> Tecnicos);

public record TarjetasIncidenciasDto(int Retrasan, int Detienen, int RegistradasTecnico, int RegistradasAsistente, int Total);

public record IncidenciaSeguimientoDto(
    string Clave, string Hora, long IdUsuario, string Tecnico, string Iniciales, long IdOs, string Numero, string Cliente,
    string TipoCodigo, string Tipo, string? Descripcion, int? DuracionMin, string Impacto, string Origen);

/// <summary>Pestaña 4 Incidencias del Día (orden cronológico).</summary>
public record IncidenciasSeguimientoDto(TarjetasIncidenciasDto Tarjetas, IReadOnlyList<IncidenciaSeguimientoDto> Filas);

public record OpcionFiltroSeguimientoDto(long Id, string Nombre);
public record OpcionCodigoSeguimientoDto(string Codigo, string Nombre);

/// <summary>Opciones de los filtros globales (técnicos, clientes y zonas con servicios hoy; estados y tipos del catálogo).</summary>
public record OpcionesFiltrosSeguimientoDto(
    IReadOnlyList<OpcionFiltroSeguimientoDto> Tecnicos, IReadOnlyList<OpcionFiltroSeguimientoDto> Clientes, IReadOnlyList<string> Zonas,
    IReadOnlyList<OpcionCodigoSeguimientoDto> Tipos, IReadOnlyList<OpcionCodigoSeguimientoDto> Estados);

/// <summary>Posición GPS que envía la app del técnico mientras su servicio está en curso (alimenta la bandeja de seguimiento).</summary>
public class RegistrarUbicacionDto
{
    public decimal? Latitud         { get; set; }
    public decimal? Longitud        { get; set; }
    public decimal? PrecisionMetros { get; set; }
}

public record UbicacionRegistradaDto(bool Guardada);
