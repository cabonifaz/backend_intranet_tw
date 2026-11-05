namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-03 — Agenda de servicios programados ──────────────────────

/// <summary>Tarjeta de la agenda del técnico (una OS).</summary>
public record ServicioProgramadoMovilDto(
    long    IdOs,
    string  NumeroOs,
    string? NumeroRq,
    string? NumeroOm,
    string? Cliente,
    string? FechaEjecucion,
    string? HoraInicio,
    string  EstadoOs,
    string? Sede,
    string? Responsable,
    int     ObjetivosTotal,
    int     ObjetivosCompletados,
    bool    ClienteConfirmado,
    string  EstadoSsoma,
    int     AlertasPredictivas,
    string  EstadoGeneral,
    string? MotivoBloqueo,
    string? HoraFin,            // horario del servicio: inicio–fin ("HH:mm")
    string? TipoServicio,
    int     NumeroTecnicos,     // equipo de trabajo (principal + apoyo)
    string? AlertaPredictiva);  // texto de la alerta sin resolver de mayor prioridad (máx. 120 caracteres)
