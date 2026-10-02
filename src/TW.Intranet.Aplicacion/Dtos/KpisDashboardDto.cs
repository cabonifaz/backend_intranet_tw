namespace TW.Intranet.Aplicacion.Dtos;

public record KpisDashboardDto(
    int     ServiciosProgramados,
    int     ServiciosEnEjecucion,
    int     ExpedientesBloqueados,
    int     PendientesSsoma,
    int     PendientesConformidad,
    int     ListosFacturar,
    int     SlaVencidos,
    int     TecnicosEnRuta,
    decimal CumplimientoSla,
    decimal VariacionSla
);
