namespace TW.Intranet.Aplicacion.Dtos;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HU-55 — Registrar el informe de un equipo desde la intranet (Asistente de Seguimiento / Jefe de Operaciones)
// Cuando el cliente no deja usar celular en planta, quien registra hace en la intranet el trabajo del técnico en un equipo. El informe queda a nombre del técnico
// asignado y se guarda quién lo registró (id_registrado_por) y la vía ('intranet'). Sin GPS. Permiso: seg_registrar_informe.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// <summary>Una fila del contexto de registro (solo lectura): OS, cliente y planta, equipo, técnico asignado, estado del equipo y de la sesión de registro.</summary>
public record ContextoRegistroIntranetFilaDto(
    long      IdOs,
    string?   NumeroOs,
    string?   TipoOrden,
    string?   NumeroRq,
    string?   EstadoOs,
    string?   Cliente,
    string?   Ruc,
    string?   Planta,
    string?   DireccionPlanta,
    long      IdOsEquipo,
    long?     IdEquipo,
    string?   EquipoNombre,
    int?      NumeroEquipo,
    string?   NumeroSerie,
    string?   CodigoCliente,
    string?   CodigoTw,
    string?   Marca,
    string?   Modelo,
    long?     IdTecnico,
    string?   Tecnico,
    bool      InformeFisico,
    string?   EstadoEquipo,
    bool      Iniciado,
    bool      InformeGenerado,
    string?   NumeroInforme,
    long?     IdInforme,
    bool      PuedeIniciar,
    string?   MotivoNoPuede,
    bool      RegistroActivo,
    long?     RegistradorId,
    string?   RegistradorNombre,
    bool      RegistroPropio,
    DateTime? RegistroUltimaActividad,
    bool      ActividadPreviaTecnico,
    string?   OtroEquipoAbierto);

/// <summary>Una etapa del Hard Stop (variables · fotos · ensayos · cabecera · correlativo) con su estado: conforme · en_curso · pendiente · bloqueado · no_conforme.</summary>
public record EtapaRegistroIntranetDto(int Orden, string Codigo, string Nombre, string Estado, string? Detalle);

/// <summary>Un ítem de catálogo. Clasificacion = padre (por ejemplo, la clasificación a la que pertenece un componente de falla).</summary>
public record CatalogoItemRegistroIntranetDto(string Codigo, string Nombre, string? Clasificacion, int Orden);

/// <summary>
/// "Contexto de registro": todo lo que necesita el asistente para arrancar, en una sola llamada. Catalogos por nombre: procedencia, tipo_equipo, forma_plato,
/// checklist_os, checklist_om, severidad, estado_equipo, clasificacion_falla, componente_falla y motivo_manual.
/// </summary>
public record ContextoRegistroIntranetDto(
    ContextoRegistroIntranetFilaDto                                           Contexto,
    IReadOnlyList<EtapaRegistroIntranetDto>                                   Etapas,
    IReadOnlyDictionary<string, IReadOnlyList<CatalogoItemRegistroIntranetDto>> Catalogos);

/// <summary>
/// Cuerpo de "iniciar-registro". Inicio y Fin = hora de Lima en que se hizo el trabajo en el equipo (ISO 8601 sin zona; con zona o "Z" se respeta). Motivo = código de
/// MOTIVO_CAMBIO_MANUAL (por ejemplo PLANTA_SIN_CELULAR). Comentario opcional (hasta 300).
/// </summary>
public class PeticionIniciarRegistroIntranetDto
{
    public string? Inicio     { get; set; }
    public string? Fin        { get; set; }
    public string? Motivo     { get; set; }
    public string? Comentario { get; set; }
}

/// <summary>Resultado de "iniciar-registro". Idempotente = ya tenía una sesión activa: se renovó y no se duplicó nada.</summary>
public record ResultadoIniciarRegistroIntranetDto(long IdRegistro, bool Idempotente, string? EstadoOs, string? EstadoEquipo, long IdTecnico, int TiempoAplicadoMin);

/// <summary>Lo que devuelve la autorización de cada llamada: el técnico en cuyo nombre se actúa y la sesión de registro (informe físico del servicio incluido).</summary>
public record AutorizacionRegistroIntranetDto(long IdTecnico, long? IdRegistro, bool InformeFisico);

/// <summary>Cuerpo de "pausar-equipo-abierto": por qué se pausa el otro equipo que el técnico dejó en ejecución.</summary>
public class PeticionPausarEquipoAbiertoIntranetDto
{
    public string? Motivo { get; set; }
}

public record ResultadoPausarEquipoAbiertoIntranetDto(long IdOs, long IdOsEquipo, string? Equipo);

/// <summary>Cuerpo de la firma "cliente ausente" de un responsable (la firma por dispositivo no existe en este flujo).</summary>
public class PeticionFirmaAusenteIntranetDto
{
    public string? Motivo { get; set; }
}

/// <summary>
/// "Informe en curso": lo ya cargado del equipo para retomar el registro. Cada parte puede venir nula si todavía no se puede leer (por ejemplo, el equipo aún no
/// está iniciado); entonces Avisos dice por qué.
/// </summary>
public record InformeEnCursoIntranetDto(
    TrabajoEquipoMovilDto?     Trabajo,
    EvidenciasMovilDto?        Evidencias,
    EnsayosMovilDto?           Ensayos,
    CabeceraInformeMovilDto?   Cabecera,
    IReadOnlyList<string>      Avisos);
