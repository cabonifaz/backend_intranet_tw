using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-36 Programación de OS y asignación de recursos (Sprint 5).</summary>
public interface IProgramacionRepositorio
{
    Task<RespuestaDto<FichaProgramacionDto>> ObtenerFichaAsync(long idOs, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<BusquedaTecnicosDto>> BuscarTecnicosAsync(
        long idOs, FiltroTecnicosProgramacion filtro, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<ProgramacionCreadaDto>> CrearAsync(NuevaProgramacion programacion, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<DerivacionSsomaDto>> DerivarSsomaAsync(NuevaDerivacionSsoma derivacion, long idUsuario, CancellationToken ct);
}
