using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Trabajo en el equipo y variables ambientales de la app móvil (App Mobile HU-08 / HU-09).</summary>
public interface ITrabajoEquipoMovilRepositorio
{
    Task<RespuestaDto<TrabajoEquipoMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);

    /// <summary>capturadoUtc: hora (UTC, sin zona) del teléfono; null = la del servidor.</summary>
    Task<RespuestaDto<ResultadoVariablesAmbientalesMovilDto>> GuardarVariablesAsync(
        long idUsuario, long idOs, long idOsEquipo, decimal temperatura, decimal humedad, string? procedencia, DateTime? capturadoUtc, CancellationToken ct);
}
