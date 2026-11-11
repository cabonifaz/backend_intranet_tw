namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-15 — Cabecera del informe · HU-16 — Hard Stop de cierre ──────────────────────

/// <summary>Opción de una lista (tipo de equipo, clasificación o componente de una falla). Padre = clasificación del componente.</summary>
public record OpcionInformeMovilDto(string Codigo, string Nombre, string? Clasificacion);

/// <summary>Pestaña Datos: informe, RQ, orden, cliente, equipo, datos del informe y "Quién atiende en planta".</summary>
public record DatosInformeMovilDto(
    long IdOs, string NumeroOs, string TipoOrden, string? NumeroRq, long? IdInforme, string? NumeroInforme, bool Generado, bool PuedeEditar,
    string? Empresa, string? Ruc, string? Direccion, string? Contacto, string? ContactoCargo, string? ContactoTelefono, string? ContactoCorreo,
    string? Marca, string? Modelo, string? NumSerie, string? CodigoCliente, string? CodigoTw, string? CapacidadMax, string? D, string? E, string? Ubicacion, string? Clase,
    string? Propuesta, string? Comercial, string? Tecnico, string? Fecha, string? HoraInicio, string? HoraFin, string? TipoServicio,
    string? ResponsableNombre, string? ResponsableCargo, string? ResponsableTelefono, DateTime? GuardadaEn);

/// <summary>Un paso del checklist de Detalle Serv. (catálogo del tipo de orden) y si el técnico lo marcó.</summary>
public record PasoChecklistMovilDto(string Codigo, string Titulo, int Orden, bool Marcado);

/// <summary>Pestaña Detalle Serv.: tipo de equipo, celdas (mV), pruebas por sumatoria y por comparación, anillos de fijación y checklist. Detalle nulo = aún no guardado.</summary>
public record DetalleServicioInformeMovilDto(
    string? TipoEquipo, IReadOnlyList<decimal> Celdas, decimal? SumatoriaHasta, decimal? ComparacionHasta, bool? AnillosFijacion, bool Guardado, IReadOnlyList<PasoChecklistMovilDto> Checklist);

public record RecomendacionInformeMovilDto(long IdRecomendacion, string Codigo, string Titulo, string? Descripcion, string Prioridad, string? Plazo);

/// <summary>Una lectura de la prueba que justifica una falla: L e I digitados, E y EMP calculados por el servidor.</summary>
public record PruebaFallaMovilDto(string Tipo, int Orden, int? Posicion, decimal Carga, decimal Indicacion, decimal Error, decimal? Emp, string? Resultado);

public record FallaInformeMovilDto(
    long IdObservacion, string Codigo, string Clasificacion, string Componente, string? ClasificacionNombre, string? ComponenteNombre, string Descripcion, string Severidad,
    IReadOnlyList<long> Fotos, IReadOnlyList<PruebaFallaMovilDto> Pruebas);

/// <summary>Una indicación de las pruebas generales (HU-10): carga, indicación, error, EMP y si es un error crítico.</summary>
public record LecturaGeneralMovilDto(int Orden, decimal? Carga, decimal? Indicacion, decimal? Error, decimal? Emp, string? Resultado, bool Critico);

/// <summary>Una carga de prueba de excentricidad con las indicaciones de sus posiciones.</summary>
public record CargaExcentricidadMovilDto(int Grupo, decimal? Carga, IReadOnlyList<LecturaGeneralMovilDto> Lecturas);

/// <summary>Pruebas generales (formato resumido): lo que guardó Ensayos y Calibración. Finalizado = la etapa de ensayos ya se cerró.</summary>
public record PruebasGeneralesMovilDto(bool Finalizado, string? ErrorCritico, IReadOnlyList<LecturaGeneralMovilDto> Pesaje, IReadOnlyList<CargaExcentricidadMovilDto> Excentricidad);

public record DiagnosticoInformeMovilDto(string? SeveridadGeneral, string? EstadoEquipo, bool RevisionJefatura, bool Precotizacion, bool SegundaVisita, bool AplicaGarantia);

public record OpcionesInformeMovilDto(
    IReadOnlyList<OpcionInformeMovilDto> TiposEquipo, IReadOnlyList<OpcionInformeMovilDto> Clasificaciones, IReadOnlyList<OpcionInformeMovilDto> Componentes);

/// <summary>Las 3 pestañas de la Cabecera del informe del equipo.</summary>
public record CabeceraInformeMovilDto(
    DatosInformeMovilDto Datos, DetalleServicioInformeMovilDto Detalle,
    IReadOnlyList<RecomendacionInformeMovilDto> Recomendaciones, bool SinRecomendaciones,
    IReadOnlyList<FallaInformeMovilDto> Fallas, bool SinFallas,
    PruebasGeneralesMovilDto PruebasGenerales, string? ComentarioPruebas, DiagnosticoInformeMovilDto Diagnostico, OpcionesInformeMovilDto Opciones);

// ── Lo que envía la app al guardar (una sección que no viene no se toca) ────────────────────────

public record DatosGuardarInformeMovilDto(string? ResponsableNombre, string? ResponsableCargo, string? ResponsableTelefono);

public record DetalleGuardarInformeMovilDto(
    string? TipoEquipo, List<decimal>? Celdas, decimal? SumatoriaHasta, decimal? ComparacionHasta, bool? AnillosFijacion, List<string>? Checks);

public record RecomendacionGuardarInformeMovilDto(string? Titulo, string? Descripcion, string? Prioridad);

public record PruebaGuardarInformeMovilDto(string? Tipo, int? Posicion, decimal? Carga, decimal? Indicacion);

public record FallaGuardarInformeMovilDto(
    string? Clasificacion, string? Componente, string? Severidad, string? Descripcion, List<long>? Fotos, List<PruebaGuardarInformeMovilDto>? Pruebas);

public record DiagnosticoGuardarInformeMovilDto(string? SeveridadGeneral, string? EstadoEquipo, bool? RevisionJefatura, bool? Precotizacion, bool? SegundaVisita, bool? AplicaGarantia);

public record GuardarCabeceraInformeMovilDto(
    DatosGuardarInformeMovilDto? Datos, DetalleGuardarInformeMovilDto? Detalle,
    List<RecomendacionGuardarInformeMovilDto>? Recomendaciones, bool? SinRecomendaciones,
    List<FallaGuardarInformeMovilDto>? Fallas, bool? SinFallas,
    string? ComentarioPruebas, DiagnosticoGuardarInformeMovilDto? Diagnostico);

/// <summary>Resultado de guardar la cabecera (la app vuelve a leerla para pintar lo calculado: E, EMP y conformidad).</summary>
public record ResultadoGuardarCabeceraMovilDto(long IdInforme, DateTime? GuardadaEn, int NFallas, int NRecomendaciones);

/// <summary>Foto de una falla ya subida: su id se envía en "fotos" de la falla al guardar la cabecera.</summary>
public record FotoFallaMovilDto(long IdEvidencia);

// ── HU-16 — Hard Stop ───────────────────────────────────────────────────────────────────────────

/// <summary>Una etapa con su estado (conforme · en_curso · pendiente · bloqueado · no_conforme) y los pendientes con su texto.</summary>
public record EtapaCierreMovilDto(int Orden, string Codigo, string Nombre, string Estado, string? Detalle, IReadOnlyList<string> Pendientes);

/// <summary>Respuesta del Hard Stop: PuedeGenerar = las 5 etapas conformes, equipo en ejecución e informe aún sin generar.</summary>
public record CierreEquipoMovilDto(
    bool PuedeGenerar, bool YaGenerado, string? NumeroInforme, int Conformes, int Total, int Pendientes, string EstadoEquipo, string Equipo, string NumeroOs,
    IReadOnlyList<EtapaCierreMovilDto> Etapas);

public record InformeGeneradoMovilDto(long IdInforme, string NumeroInforme, string EstadoEquipo, bool Repetida);
