namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Tarjetas resumen de la bandeja de propuestas (HU-08). Coincide con KpisPropuestas del front.</summary>
public record KpisPropuestasDto(
    int     Pendientes,
    decimal VariacionPendientes,
    int     PorVistoBueno,
    int     PorEnviar,
    int     EnSeguimiento,
    int     SlaVencidos
);
