namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-37 Detalle de la Programación y registro de la confirmación con el cliente (Sprint 5) ─────────────

/// <summary>Acciones del detalle según los permisos del usuario del token y el estado de la programación.</summary>
public record AccionesDetalleProgramacionDto(
    bool PuedeRegistrarRespuesta,
    bool PuedeReasignar,
    bool PuedeReprogramar,
    /// <summary>true = el usuario reprograma directo (jefe); false = debe pasar por solicitud (asistente). HU-38.</summary>
    bool ReprogramacionDirecta,
    bool ReprogramacionRequiereSolicitud,
    bool PuedeCancelar,
    /// <summary>Programación confirmada y usuario con permiso de jefe: habilita Gestionar Viáticos (HU-45).</summary>
    bool PuedeGestionarViaticos,
    bool PuedeVerExpediente);

/// <summary>Bloque DATOS DE LA PROGRAMACIÓN, con los enlaces cruzados (OS, expediente y propuesta) y el próximo paso.</summary>
public class CabeceraProgramacionDto
{
    public long     IdProgramacion   { get; init; }
    public string   Codigo           { get; init; } = "";
    /// <summary>pendiente_confirmacion | confirmada | cancelada.</summary>
    public string   Estado           { get; init; } = "";
    /// <summary>Etiqueta para mostrar: Pendiente confirmación cliente | Programado | Cancelada.</summary>
    public string   EstadoLabel      { get; init; } = "";
    public long     IdOs             { get; init; }
    public string   NumeroOs         { get; init; } = "";
    public string   Tipo             { get; init; } = "OS";
    public string?  EstadoOs         { get; init; }
    public long?    IdExpediente     { get; init; }
    public string?  NumeroExpediente { get; init; }
    public long?    IdCliente        { get; init; }
    public string?  RazonSocial      { get; init; }
    public string?  Ruc              { get; init; }
    public long?    IdSede           { get; init; }
    public string?  Sede             { get; init; }
    public string?  Ubicacion        { get; init; }
    public long?    IdPropuesta      { get; init; }
    public string?  NumeroPropuesta  { get; init; }
    public int?     VersionPropuesta { get; init; }
    public int?     IdTipoServicio   { get; init; }
    public string?  TipoServicio     { get; init; }
    public string?  FechaEjecucion   { get; init; }
    public string?  HoraInicio       { get; init; }
    public string?  HoraFin          { get; init; }
    public decimal? DuracionHoras    { get; init; }
    public string?  Observaciones    { get; init; }
    public string?  TecnicoPrincipal { get; init; }
    public int      NumeroTecnicos   { get; init; }
    public int      NumeroEquipos    { get; init; }
    public int      NumeroConceptos  { get; init; }
    public string   ProximoPaso      { get; init; } = "";
    public DateTime? CreadoEn        { get; init; }
    public string?  CreadoPor        { get; init; }
    /// <summary>true = hay una habilitación SSOMA que bloquea la ejecución hasta reasignar o reprogramar.</summary>
    public bool     BloqueoSsomaActivo { get; init; }
    public required AccionesDetalleProgramacionDto Acciones { get; init; }
}

/// <summary>Técnico de la programación. SsomaAlProgramar es lo guardado al crearla; SsomaActual, la evaluación de hoy.</summary>
public record TecnicoDetalleProgramacionDto(
    long IdUsuario, string Nombre, string? Cargo, string Rol, string? SsomaAlProgramar, string? SsomaActual, string? SsomaMotivo);

public record EquipoDetalleProgramacionDto(long IdEquipo, string? CodigoTw, string? Marca, string? Modelo, string? NumeroSerie);

/// <summary>Ítem del checklist de validación (siempre 4: técnico asignado, equipos reservados, SSOMA habilitado, cronograma válido).</summary>
public record ItemChecklistProgramacionDto(string Item, string Titulo, bool Cumple, bool RequiereAccion, string? Detalle);

/// <summary>Alerta SSOMA sobrevenida. Severidad: critica (bloquea la ejecución) o advertencia (vence pronto).</summary>
public record AlertaSsomaProgramacionDto(
    string Severidad, long IdUsuario, string Tecnico, string? Requisito, string? Situacion, string? EstadoDocumento,
    string? FechaVencimiento, int? DiasVencido, bool YaVencio, string? Mensaje);

/// <summary>Evento del historial. Tipo: programacion | respuesta_cliente | reprogramacion | aprobacion | cancelacion | estado.</summary>
public record EventoProgramacionDto(
    DateTime? Fecha, string Tipo, string Titulo, string? Descripcion, string? Usuario,
    string? EstadoAnterior, string? EstadoNuevo, string? Motivo);

public record RespuestaClienteProgramacionDto(
    long Id, string Canal, string CanalLabel, string Resultado, string ResultadoLabel,
    string? Comentario, DateTime? FechaRegistro, string? RegistradoPor);

public record DetalleProgramacionDto(
    CabeceraProgramacionDto Programacion,
    IReadOnlyList<TecnicoDetalleProgramacionDto> Tecnicos,
    IReadOnlyList<EquipoDetalleProgramacionDto> Equipos,
    IReadOnlyList<ConceptoProgramacionDto> Conceptos,
    IReadOnlyList<ItemChecklistProgramacionDto> Checklist,
    IReadOnlyList<AlertaSsomaProgramacionDto> AlertasSsoma,
    IReadOnlyList<EventoProgramacionDto> Historial,
    IReadOnlyList<RespuestaClienteProgramacionDto> Respuestas);

/// <summary>
/// Cuerpo de POST /api/operaciones/programacion/programaciones/{idProgramacion}/respuesta-cliente.
/// Canal: correo | whatsapp | llamada | presencial. Resultado: acepto | pidio_reprogramar | cancelo. Comentario opcional (300).
/// </summary>
public class RegistrarRespuestaClienteDto
{
    public string? Canal      { get; set; }
    public string? Resultado  { get; set; }
    public string? Comentario { get; set; }
}

/// <summary>Respuesta ya validada que recibe el repositorio.</summary>
public record NuevaRespuestaCliente(long IdProgramacion, string Canal, string Resultado, string? Comentario);

/// <summary>
/// Respuesta registrada. SiguienteAccion: gestionar_viaticos (aceptó) · reprogramar | solicitar_reprogramacion (pidió reprogramar,
/// según el rol) · cancelar_programacion (canceló, con motivo tipificado obligatorio). Las dos últimas las ejecuta la HU-38.
/// </summary>
public record RespuestaClienteRegistradaDto(
    long IdConfirmacion, long IdProgramacion, string Codigo, string Estado, string EstadoLabel, string Canal, string Resultado,
    string? Comentario, long IdOs, string NumeroOs, string SiguienteAccion, bool PuedeGestionarViaticos,
    bool RequiereSolicitud, bool RequiereMotivoCancelacion, IReadOnlyList<string> Advertencias);
