namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-02 — Menú principal ────────────────────────────────────────

/// <summary>Indicadores del menú de la app para el técnico que inició sesión.</summary>
public record ResumenMenuMovilDto(
    int                      ServiciosAsignados,
    int                      ServiciosHoy,
    ProximoServicioMovilDto? ProximoServicio);

/// <summary>OS en curso o la siguiente por fecha y hora (banner "Próximo Hit").</summary>
public record ProximoServicioMovilDto(
    long    IdOs,
    string  Numero,
    string? Cliente,
    string? Sede,
    string? Distrito,
    string? TipoServicio,
    string? FechaEjecucion,
    string? HoraInicio,
    string  Estado);
