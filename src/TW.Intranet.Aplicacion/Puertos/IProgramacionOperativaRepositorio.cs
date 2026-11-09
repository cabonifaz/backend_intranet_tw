using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-35 Bandeja de Programación Operativa (solo lectura).</summary>
public interface IProgramacionOperativaRepositorio
{
    Task<RespuestaDto<ResumenProgramacionDto>> ObtenerResumenAsync(
        DateTime? fechaSemana, string? busqueda, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<ListaProgramacionDto>> ObtenerPendientesAsync(
        FiltrosProgramacionDto filtros, bool exportar, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<ListaProgramacionDto>> ObtenerProgramadosAsync(
        FiltrosProgramacionDto filtros, bool exportar, long idUsuario, CancellationToken ct);
}
