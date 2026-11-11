namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-29 / HU-30 — Panel de campo en tiempo real y Seguimiento del servicio (Jefe de Área) ────────────────

/// <summary>KPIs del Panel de Campo (servicios de HOY del alcance del jefe; las banderas no son excluyentes entre sí).</summary>
public record PanelCampoKpisDto(int Programados, int EnRuta, int Ejecucion, int Demora, int Incidencia, int Finalizados, string? Actualizado, int RefrescoSegundos);

/// <summary>
/// Un pin del mapa por técnico. Estado = el de su servicio más urgente (sin_salir, en_ruta, en_planta, en_ejecucion, con_demora, con_incidente, finalizado).
/// Latitud/Longitud NULL = el técnico aún no envía posición hoy.
/// </summary>
public record PanelCampoPinDto(long IdUsuario, string Tecnico, string Iniciales, string Estado, decimal? Latitud, decimal? Longitud, int? MinutosUbicacion,
                               long? IdOs, string? NumeroOs, string? Cliente);

/// <summary>Alerta del panel. Tipo: error_critico · incidente · demora · perdida_contacto · gps_parado · sin_ingreso_post_llegada · sin_iniciar_servicio. Severidad: critica | advertencia.</summary>
public record PanelCampoAlertaDto(string Clave, string Tipo, string Severidad, string Titulo, string? Detalle, long IdOs, string NumeroOs, string? Cliente,
                                  string? Tecnico, string? Equipo, int Minutos);

public record PanelCampoDto(PanelCampoKpisDto Kpis, List<PanelCampoPinDto> Pines, List<PanelCampoAlertaDto> Alertas);

/// <summary>Contadores de los chips de "Servicios activos" (sobre todo el alcance, sin búsqueda ni filtro).</summary>
public record ChipsServiciosDto(int Activos, int ConDemora, int Incidencias, int Finalizados, string? Actualizado, int RefrescoSegundos);

/// <summary>Una tarjeta de "Servicios activos". Eta solo en ruta. AvancePct es una estimación por hitos (ver SP_ObtenerServiciosJefaturaMovil).</summary>
public record ServicioActivoDto(long IdOs, string Numero, string? Cliente, string Estado, long? IdTecnico, string? Tecnico, string Iniciales, string? Lugar,
                                string? HoraProgramada, string? Llegada, string? Eta, int AvancePct, int? MinutosUbicacion);

public record ServiciosJefaturaDto(ChipsServiciosDto Chips, List<ServicioActivoDto> Servicios);

/// <summary>
/// Cabecera del detalle de un servicio. SlaPct = puntualidad de llegada (estimación; NULL sin llegada). PuedeCambiarEstado = el usuario tiene los permisos del
/// seguimiento operativo (seg_registrar y seg_bandeja) y el servicio no está finalizado.
/// </summary>
public record ServicioCabeceraDto(long IdOs, string Numero, string? Tipo, string? Cliente, string? Lugar, string Estado, string EstadoOs, long? IdTecnico,
                                  string? Tecnico, string? CargoTecnico, string? TelefonoTecnico, string? HoraProgramada, string? Llegada, int? SlaPct,
                                  int AvancePct, int Equipos, int Ejecutados, string? ContactoNombre, string? ContactoTelefono, bool PuedeCambiarEstado,
                                  string? Actualizado);

/// <summary>Hito del servicio. Estado: hecho | actual | pendiente. Tono: verde | azul | naranja | rojo | gris.</summary>
public record HitoServicioDto(string Codigo, string Titulo, string? Detalle, string? Hora, string Estado, string Tono);

/// <summary>Estado al que se puede avanzar (solo hacia adelante): salida, en_ruta, llegada, ingreso, inicio, finalizado.</summary>
public record EstadoPermitidoDto(string Codigo, string Nombre);

public record MotivoCambioDto(int IdMotivo, string Nombre);

public record ServicioJefaturaDto(ServicioCabeceraDto Cabecera, List<HitoServicioDto> Hitos, List<EstadoPermitidoDto> EstadosPermitidos, List<MotivoCambioDto> Motivos);

/// <summary>Resumen de "Ubicación y ruta". Distancia en línea recta a la planta; velocidad entre las dos últimas posiciones; Eta (HH:MM) solo en ruta.</summary>
public record RutaResumenDto(long IdOs, string Numero, string? Cliente, string Estado, long? IdTecnico, string? Tecnico, string? TelefonoTecnico,
                             decimal? Latitud, decimal? Longitud, int? MinutosUbicacion, decimal? VelocidadKmh, int? DistanciaM,
                             decimal? DestinoLatitud, decimal? DestinoLongitud, string? DestinoNombre, decimal? OrigenLatitud, decimal? OrigenLongitud,
                             string? Eta, string? EtaProgramada, string? DemoraTexto, string? DemoraOrigen, string? ContactoNombre, string? ContactoTelefono,
                             string? Actualizado);

public record PuntoGpsServicioDto(decimal Latitud, decimal Longitud, string? Hora);

/// <summary>Evento en ruta. Tono: verde (hito OK) | naranja o rojo (demora) | amarillo (alerta).</summary>
public record EventoRutaDto(string? Hora, string Titulo, string? Detalle, string Badge, string Tono);

public record RutaServicioDto(RutaResumenDto Resumen, List<PuntoGpsServicioDto> Recorrido, List<EventoRutaDto> Eventos);

/// <summary>Cambio manual de estado (solo avanzar). NuevoEstado: salida | en_ruta | llegada | ingreso | inicio | finalizado. Comentario de 10 a 1000 caracteres.</summary>
public record CambiarEstadoServicioDto(string? NuevoEstado, int? IdMotivo, string? Comentario);

/// <summary>Constancia del aviso dado al cliente (5 a 450 caracteres). No envía nada al cliente.</summary>
public record AvisarClienteDto(string? Mensaje);

public record RegistroSeguimientoResultadoDto(long IdRegistro, string Modo, int Notificados, string? EstadoNuevo);
