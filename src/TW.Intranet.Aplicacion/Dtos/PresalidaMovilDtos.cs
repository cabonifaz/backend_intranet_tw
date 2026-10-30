namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-04 — Detalle del servicio y checklist de pre-salida ──────────

/// <summary>Detalle de la OS para el técnico (destino, contacto, documentos, alertas, riesgos…).</summary>
public record DetalleServicioMovilDto(
    ServicioDetalleMovilDto           Servicio,
    List<AlertaServicioMovilDto>      Alertas,
    List<RiesgoServicioMovilDto>      Riesgos,
    List<RepuestoServicioMovilDto>    Repuestos,
    List<HistorialServicioMovilDto>   Historial,
    List<DocumentoServicioMovilDto>   Documentos);

public record ServicioDetalleMovilDto(
    long    IdOs,
    string  NumeroOs,
    string? NumeroRq,
    string? NumeroOm,
    string? Cliente,
    int     IdTipoServicio,
    string? TipoServicio,
    string? FechaEjecucion,
    string? HoraInicio,
    string  EstadoOs,
    string? Sede,
    string? Direccion,
    string? ContactoNombre,
    string? ContactoCargo,
    string? ContactoTelefono,
    string? Responsable,
    bool    ClienteConfirmado,
    string  EstadoSsoma,
    int     ObjetivosTotal,
    string? NotasOperativas);

public record AlertaServicioMovilDto(long IdAlerta, string? Tipo, string Descripcion, string? Prioridad, string? Equipo, DateTime? FechaGeneracion);

public record RiesgoServicioMovilDto(int IdRiesgo, string? Nombre, string? Codigo, string? Icono, string? Observacion);

public record RepuestoServicioMovilDto(long IdItem, string Descripcion, bool Asignado);

/// <summary>Una modificación: valor anterior y actual (equipo o servicio).</summary>
public record HistorialServicioMovilDto(
    DateTime? Fecha,
    string    Origen,
    string?   Titulo,
    string?   Referencia,
    string?   ValorAnterior,
    string?   ValorNuevo,
    string?   Detalle,
    string?   Usuario);

public record DocumentoServicioMovilDto(long IdDocumento, string NombreArchivo, string? Tipo, int Version, DateTime? FechaCarga);

/// <summary>Datos crudos con los que se arma el checklist (salen de SP_ObtenerChecklistSalidaMovil).</summary>
public record HechosChecklistSalidaDto(
    long      IdOs,
    string    NumeroOs,
    string?   Cliente,
    string?   FechaEjecucion,
    string?   HoraInicio,
    string?   Tecnico,
    string    EstadoOs,
    int       IdTipoServicio,
    bool      ClienteConfirmado,
    string    EstadoSsoma,
    bool      TieneOc,
    int       RepuestosTotal,
    int       RepuestosPendientes,
    int       AlertasPendientes,
    bool      ExpedienteRevisado,
    bool      EppRevisado,
    bool      MaterialesListos,
    bool      HerramientasListas,
    bool      PesasPatronAsignadas,
    string?   AutorizacionEstado,
    string?   AutorizacionComentario,
    DateTime? AutorizacionSolicitadaEn,
    DateTime? AutorizacionResueltaEn,
    string?   AutorizacionJefe,
    string?   AreaAutorizaCodigo,   // servicio_tecnico | metrologia | null (la RQ no indica área)
    string?   AreaAutoriza,         // "Servicio Técnico" | "Metrología"
    string?   CargoEncargado,       // "Jefe de Servicio Técnico" | "Jefe de Metrología"
    string?   EncargadoArea);       // nombre(s) del encargado activo

/// <summary>Un ítem del checklist. Estado: conforme | pendiente | bloqueado | no_aplica | opcional.</summary>
public record ItemChecklistSalidaDto(
    string  Codigo,
    string  Nombre,
    string  Tipo,          // manual (lo confirma el técnico) | automatico (sale de los datos) | autorizacion
    bool    Obligatorio,
    string  Estado,
    string? Detalle,
    bool    Editable);

/// <summary>Visto bueno del encargado del área. Estado: pendiente | aprobada | rechazada.</summary>
public record AutorizacionSalidaDto(string Estado, string? Jefe, string? Comentario, DateTime? SolicitadaEn, DateTime? ResueltaEn);

/// <summary>Quién autoriza la salida según la RQ: área y encargado(s).</summary>
public record AreaAutorizaSalidaDto(string? Codigo, string? Area, string? Cargo, string? Encargado);

/// <summary>Checklist de pre-salida listo para la app.</summary>
public record ChecklistSalidaMovilDto(
    long                          IdOs,
    string                        NumeroOs,
    string?                       Cliente,
    string?                       FechaEjecucion,
    string?                       HoraInicio,
    string?                       Tecnico,
    string                        EstadoOs,
    List<ItemChecklistSalidaDto>  Items,
    List<string>                  Faltantes,
    bool                          PuedeIniciar,
    bool                          SaleConVistoBueno,
    bool                          PuedeSolicitarAutorizacion,
    bool                          TrasladoIniciado,
    AutorizacionSalidaDto?        Autorizacion,
    AreaAutorizaSalidaDto         AreaAutoriza);

/// <summary>El técnico marca o desmarca un ítem manual del checklist.</summary>
public record MarcarItemChecklistDto(bool Confirmado);

/// <summary>El técnico pide el visto bueno (motivo opcional, máx. 300 caracteres).</summary>
public record SolicitarAutorizacionSalidaDto(string? Motivo);

// ── Intranet: visto bueno del encargado del área (Servicio Técnico / Metrología) ──

/// <summary>El jefe aprueba o rechaza la salida (comentario obligatorio al rechazar).</summary>
public record ResolverAutorizacionSalidaDto(bool Aprobar, string? Comentario);

/// <summary>Fila de la bandeja de autorizaciones de salida del jefe.</summary>
public record AutorizacionSalidaBandejaDto(
    long      IdAutorizacion,
    long      IdOs,
    string    NumeroOs,
    string?   Cliente,
    string?   FechaEjecucion,
    string?   HoraInicio,
    string    EstadoOs,
    string?   Tecnico,
    string?   Motivo,
    string?   Pendientes,
    string    Estado,
    string?   AreaCodigo,
    string?   Area,
    DateTime? SolicitadaEn,
    string?   Jefe,
    DateTime? ResueltaEn,
    string?   Comentario);
