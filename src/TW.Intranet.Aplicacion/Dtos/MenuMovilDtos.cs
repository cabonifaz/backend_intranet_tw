namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-02 — Menú principal ────────────────────────────────────────

/// <summary>Indicadores del menú de la app para el técnico que inició sesión.</summary>
public record ResumenMenuMovilDto(
    int                      ServiciosAsignados,
    int                      ServiciosHoy,
    ProximoServicioMovilDto? ProximoServicio,
    decimal                  ViaticosSaldoPorRendir = 0,   // viáticos activos: asignado - rendido
    int                      ViaticosActivos = 0,
    decimal                  GastosEnRevision = 0,         // gastos rendidos esperando al Jefe de Operaciones
    int                      GastosEnRevisionCantidad = 0);

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
