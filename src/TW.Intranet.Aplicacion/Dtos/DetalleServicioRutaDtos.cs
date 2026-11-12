namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-52 Detalle del Servicio en Ruta (Sprint 5) ─────────────────────────────────────────────────────────────
// Vista OBSERVACIONAL del Asistente de Seguimiento: el contenido lo registra la app móvil. Estos DTOs solo se leen.

/// <summary>Cabecera fija del modal + pestaña Resumen (programación, métricas rápidas y datos de las pestañas condicionales).</summary>
public record CabeceraServicioRutaDto(
    long IdOs, string Numero, string Tipo, string? Propuesta, string? CodigoProgramacion, string? Expediente,
    long IdCliente, string Cliente, string? Ruc, string? Sede, string? DireccionSede, string? TipoServicio, int? MinutosEstimados, int EquiposProgramados,
    string? Norma, string? NotaProcedimiento, long? IdTecnicoLider, string? TecnicoLider, string? CargoTecnico, string? EstadoSsoma,
    string? HoraInicio, string? HoraFin, string? SalidaReal, string? PuntualidadSalida, string Estado, string FechaEjecucion,
    string UltimaActualizacion, int RefrescoSegundos, bool MostrarCierre, string? TelefonoTecnico);

public record MetricasServicioRutaDto(
    int AvancePct, int EquiposCompletados, int EquiposTotal, int DemorasIncidencias, int MinutosDemora, string? MotivoDemora, int AlertasActivas,
    int MinutosServicio, int? MinutosEstimados);

public record EquipoResumenRutaDto(long IdEquipo, string Codigo, string? Modelo, string? Serie, string EstadoEjecucion, string? EtapaActual, string? HoraCompletado, bool Observado);
public record ResponsableServicioRutaDto(long IdUsuario, string Nombre, string Rol, string? Cargo, string? Nota);
public record ContactoPlantaDto(string Nombre, string? Cargo, string? Telefono, string? Correo, string? ConfirmadoA, int? HaceMinutos);

public record DetalleServicioRutaDto(
    CabeceraServicioRutaDto Cabecera, MetricasServicioRutaDto Metricas, IReadOnlyList<EquipoResumenRutaDto> Equipos,
    IReadOnlyList<ResponsableServicioRutaDto> Responsables, ContactoPlantaDto? Contacto);

// Avance por equipos
public record EtapaEquipoRutaDto(string Etapa, int Orden, string Estado, string? Hora);
public record EquipoAvanceRutaDto(
    long IdEquipo, string Codigo, string? Modelo, string? Serie, string Estado, int Fotos, int Ensayos, int CertificadoPreliminar, int Observaciones, int Mediciones,
    string? Iniciado, string? Finalizado, int? Minutos, IReadOnlyList<EtapaEquipoRutaDto> Etapas);
public record AvanceServicioRutaDto(int EquiposCompletados, int EquiposTotal, IReadOnlyList<EquipoAvanceRutaDto> Equipos);

/// <summary>Fila común de los drill-downs del equipo (Fotos, Ensayos, Documentos, Observaciones, Mediciones).</summary>
public record ElementoEquipoRutaDto(long Id, string Titulo, string? Detalle, string? Fecha, string? Url, string? Resultado, int? UltimaHaceMin);
public record SeccionEquipoRutaDto(string Seccion, IReadOnlyList<ElementoEquipoRutaDto> Elementos);

// Mapa GPS
public record PanelGpsRutaDto(
    long IdOs, string Estado, string? Tecnico, string? Cliente, string? Sede, string? DireccionSede, decimal? LatSede, decimal? LonSede, int RadioProximidadM, bool MostrarRadio,
    decimal? Latitud, decimal? Longitud, string? UltimaUbicacion, int? DistanciaM, string? UltimaActualizacion, int? SegundosDesdeUltima, string Conexion,
    int MinutosEnPunto, int? PrecisionM, decimal? VelocidadKmh, decimal? AltitudM, int? Satelites, int? LatenciaMs,
    /// <summary>HU-20: estimación de llegada EN RUTA (minutos y hora de Lima); línea recta × 1,3 a la velocidad promedio configurada. Null si no está en ruta o no hay coordenadas de la planta.</summary>
    int? EtaMinutos = null, string? EtaHora = null,
    /// <summary>HU-20: punto de salida del recorrido (evento «Salida» o la primera posición GPS del día). La lista de la ruta va de la más reciente a la más antigua.</summary>
    decimal? OrigenLat = null, decimal? OrigenLon = null);
public record PuntoRutaDto(decimal Latitud, decimal Longitud, string Hora);
public record HitoGpsDto(string Hito, string? Hora);
/// <summary>Demora registrada desde la app con el GPS del técnico en ese momento. Fase: llegada (en ruta) | ingreso (ingreso a planta).</summary>
public record DemoraMapaDto(decimal Latitud, decimal Longitud, string Hora, string Fase, string Motivo, int DuracionMin);
public record MapaServicioRutaDto(PanelGpsRutaDto Panel, IReadOnlyList<PuntoRutaDto> Ruta, IReadOnlyList<HitoGpsDto> Cronograma,
    IReadOnlyList<DemoraMapaDto>? Demoras = null);

// Timeline
public record ConteoTimelineDto(int Hitos, int Alertas, int Incidencias, int Asistente, int Total);
public record EventoTimelineRutaDto(string Hora, string Categoria, string Origen, string Titulo, string? Detalle, string Clave,
    string? Badge = null, string? Registrador = null, string? Vinculo = null);
public record TimelineServicioRutaDto(ConteoTimelineDto Conteos, IReadOnlyList<EventoTimelineRutaDto> Eventos);

// Demoras / Incidencias
public record KpisIncidenciasRutaDto(int Total, int Retrasan, int Detienen, int PorTecnico, int PorAsistente);
public record IncidenciaServicioRutaDto(
    string Clave, string Hora, string TipoCodigo, string Tipo, string? Descripcion, int? DuracionMin, string Impacto, string Origen, string? Registrador,
    string? Evidencia, bool TieneEvidencia, string? Momento = null, decimal? Latitud = null, decimal? Longitud = null);
public record IncidenciasServicioRutaDto(KpisIncidenciasRutaDto Kpis, IReadOnlyList<IncidenciaServicioRutaDto> Filas);

// Cierre (HU-54, observacional)
public record CabeceraCierreServicioRutaDto(
    string Resultado, string ResultadoTexto, string? FinalizadoHora, int? DuracionMin, int? MinutosEstimados, int? DiferenciaMin,
    long? IdTecnico, string? Tecnico, string? Iniciales, string Rol, string CerradoPor, string Subtitulo,
    int EquiposFinalizados, int EquiposTotal, int Informes, int DemorasIncidencias, int RegistrosAsistente,
    int EquiposParciales, int EquiposPendientes, int EquiposReprogramados, int EquiposAnulados,
    string EstadoCabecera, bool ModoAuditoria, bool RegistrarHabilitado, string TooltipRegistrar, string ChipModo, string TextoActualizacion);
public record EquipoCierreRutaDto(
    long IdEquipo, string Nombre, string? Serie, string? TipoServicio, string Estado, string EstadoTexto, string? Hora,
    string? Informe, string? UrlInforme, bool ConObservaciones, string? Info, string? Vinculo, bool Destacado);
public record ActaConformidadRutaDto(
    string? Hora, string Estado, string Chip, string? Firmante, string? Cargo, string Metodo, string Tipo,
    bool GpsVerificado, string Gps, string? UrlFirma, string? Observaciones, string Nota);
public record PieCierreRutaDto(long? IdExpediente, string? Expediente, int Documentos, int EventosAuditoria);
public record OrdenCierreRutaDto(string Numero, string Estado, string? Certificado, string? FechaEmision);
public record CierreServicioRutaDto(
    CabeceraCierreServicioRutaDto Cabecera, IReadOnlyList<EquipoCierreRutaDto> Equipos, ActaConformidadRutaDto? Acta,
    PieCierreRutaDto Pie, IReadOnlyList<OrdenCierreRutaDto> Ordenes);

public record AuditoriaEntradaRutaDto(string Fecha, string Origen, string Accion, string? Usuario, string? Descripcion);
public record AuditoriaServicioRutaDto(IReadOnlyList<AuditoriaEntradaRutaDto> Entradas);

/// <summary>Archivo CSV generado por el servidor (exportación de Demoras / Incidencias).</summary>
public record ArchivoCsvDto(string NombreArchivo, byte[] Contenido);

/// <summary>Consulta del timeline ya validada.</summary>
public record ConsultaTimelineNormalizada(string Categoria, string Orden);
