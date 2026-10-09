namespace TW.Intranet.Aplicacion.Dtos;

// ─────────────────────────────────────────────────────────────────────────────
// HU-09 — Detalle y Vista Previa de Propuesta
// GET /api/crm/propuestas/{id}/detalle
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Respuesta del modal "Detalle de Propuesta".</summary>
public class PropuestaDetalleModalDto
{
    /// <summary>Misma estructura que GET /api/crm/propuestas/{id} (pestañas Resumen, Ítems, Condiciones y Equipos).</summary>
    public PropuestaDetalleDto Propuesta { get; set; } = new();

    public WorkflowPropuestaDto        Workflow   { get; set; } = new();
    public SlaPropuestaDto?            Sla        { get; set; }
    public AccionesPropuestaDto        Acciones   { get; set; } = new();

    /// <summary>Número del contrato marco vigente del cliente (dato "Contrato" del resumen). Null si no tiene.</summary>
    public string? NumeroContratoMarco { get; set; }

    public List<DocumentoVinculadoDto> Documentos { get; set; } = new();
    public List<VersionPropuestaDto>   Versiones  { get; set; } = new();
    public List<ActividadPropuestaDto> Actividad  { get; set; } = new();
}

/// <summary>
/// Workflow de aprobación: borrador → visto_bueno → envio → seguimiento → aceptacion.
/// Cada paso trae Estado = completado | actual | pendiente, o el estado terminal
/// (rechazado | anulado | vencido) en el paso donde se detuvo.
/// </summary>
public class WorkflowPropuestaDto
{
    public List<PasoWorkflowDto> Pasos { get; set; } = new();
    /// <summary>rechazado | anulado | vencido; null si el flujo sigue abierto.</summary>
    public string? EstadoTerminal { get; set; }
}

public class PasoWorkflowDto
{
    public string Codigo   { get; set; } = "";
    public string Etiqueta { get; set; } = "";
    public string Estado   { get; set; } = "pendiente";
}

/// <summary>
/// SLA de la etapa actual. Tipo "visto_bueno" (pendiente de VB, según CONFIG_SLA)
/// o "vigencia" (enviada, hasta la fecha de expiración). Null en las demás etapas.
/// </summary>
public class SlaPropuestaDto
{
    public string   Tipo             { get; set; } = "";
    public DateTime VenceEn          { get; set; }
    /// <summary>Negativo si ya venció. El front lo muestra como días u horas.</summary>
    public int      MinutosRestantes { get; set; }
    public bool     Vencido          { get; set; }
}

/// <summary>Qué botón muestra el modal (HU-09: "Editar" se reemplaza por "Generar Nueva Versión").</summary>
public class AccionesPropuestaDto
{
    public bool   PuedeEditar              { get; set; }
    public bool   PuedeGenerarNuevaVersion { get; set; }
    public bool   EsUltimaVersion          { get; set; }
    /// <summary>editar | nueva_version | ninguna</summary>
    public string AccionPrincipal          { get; set; } = "ninguna";
}

public class DocumentoVinculadoDto
{
    /// <summary>requerimiento | expediente | orden_compra | adjunto</summary>
    public string    Tipo        { get; set; } = "";
    public long?     IdEntidad   { get; set; }
    public string?   Codigo      { get; set; }
    public string?   Descripcion { get; set; }
    public string?   Estado      { get; set; }
    public string?   Url         { get; set; }
    public DateTime? Fecha       { get; set; }
    /// <summary>true para el marcador "OC (Pendiente)" cuando aún no hay orden de compra.</summary>
    public bool      EsPendiente { get; set; }
}

public class VersionPropuestaDto
{
    public long      IdPropuesta        { get; set; }
    public int       Version            { get; set; }
    public string    Estado             { get; set; } = "";
    public decimal   Total              { get; set; }
    public DateTime? FechaCreacion      { get; set; }
    public DateTime? FechaEnvio         { get; set; }
    public string?   NombreCreador      { get; set; }
    public string?   MotivoNuevaVersion { get; set; }
    public bool      EsActual           { get; set; }
}

public class ActividadPropuestaDto
{
    public long      IdAuditoria    { get; set; }
    public string    Accion         { get; set; } = "";
    public string?   EstadoAnterior { get; set; }
    public string?   EstadoNuevo    { get; set; }
    public string?   Descripcion    { get; set; }
    public DateTime? RegistradoEn   { get; set; }
    public string?   NombreUsuario  { get; set; }
}

/// <summary>Datos crudos de SP_ObtenerContextoPropuesta (uso interno: puerto → caso de uso).</summary>
public class PropuestaContextoDto
{
    public string    Estado              { get; set; } = "";
    public DateTime? FechaPdf            { get; set; }
    public DateTime? FechaEnvio          { get; set; }
    public DateTime? FechaExpiracion     { get; set; }
    public bool      EsUltimaVersion     { get; set; }
    public bool      TieneOc             { get; set; }
    public string?   SlaTipo             { get; set; }
    public DateTime? SlaVenceEn          { get; set; }
    public string?   NumeroContratoMarco { get; set; }
    /// <summary>NOW() de la BD, para medir el SLA con el mismo reloj que guardó las fechas.</summary>
    public DateTime  Ahora               { get; set; }

    public List<DocumentoVinculadoDto> Documentos { get; set; } = new();
    public List<VersionPropuestaDto>   Versiones  { get; set; } = new();
    public List<ActividadPropuestaDto> Actividad  { get; set; } = new();
}
