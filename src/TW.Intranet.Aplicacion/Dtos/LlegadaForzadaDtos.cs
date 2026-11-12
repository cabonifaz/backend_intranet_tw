namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-06 — Llegada forzada: el técnico fuera del radio pide a Jefatura que le autorice registrar su llegada ──

/// <summary>
/// Lo que la app envía al pedir la llegada forzada: la ubicación (misma validación que la llegada), cuántas veces volvió a capturarla estando fuera
/// del rango (la app exige 5; el SP lo vuelve a comprobar) y un motivo opcional.
/// </summary>
public class PeticionLlegadaForzadaDto : PeticionLlegadaMovilDto
{
    public int?    Intentos { get; set; }
    public string? Motivo   { get; set; }
}

/// <summary>Estado de la solicitud de llegada forzada de la OS, para el técnico: pendiente | aprobada | rechazada (con lo que respondió Jefatura).</summary>
public record LlegadaForzadaEstadoDto(string Estado, string? Comentario, string? Jefe, DateTime? ResueltaEn);

/// <summary>
/// Solicitud de llegada forzada vista por el encargado (bandeja de Aprobaciones y su detalle). Las horas son de Lima.
/// DistanciaMetros = a cuántos metros de la planta estaba el técnico al pedirla; Latitud/Longitud = dónde estaba; LatPlanta/LonPlanta = la planta.
/// </summary>
public record SolicitudLlegadaForzadaDto(
    long IdSolicitud, long IdOs, string NumeroOs, string? Cliente, string? Sede, string? FechaEjecucion, string? HoraInicio, string? Tecnico,
    string Estado, string? Motivo, int Intentos, decimal? Latitud, decimal? Longitud, decimal? PrecisionMetros, int? DistanciaMetros,
    decimal? LatPlanta, decimal? LonPlanta, int RadioMetros, string? AreaCodigo, string? Area, DateTime? SolicitadaEn,
    string? Jefe, DateTime? ResueltaEn, string? Comentario, DateTime? UsadaEn);
