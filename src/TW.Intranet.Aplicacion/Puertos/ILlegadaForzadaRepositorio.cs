using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Llegada forzada: solicitud del técnico y aprobación del encargado (App Mobile HU-06 / HU-31).</summary>
public interface ILlegadaForzadaRepositorio
{
    Task<RespuestaDto<bool>> SolicitarAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal precisionMetros, int intentos, string? motivo, CancellationToken ct);

    /// <summary>idOs = 0 → las pendientes que puede resolver el usuario (la bandeja); idOs &gt; 0 → la solicitud más reciente de esa OS.</summary>
    Task<RespuestaDto<List<SolicitudLlegadaForzadaDto>>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct);

    Task<RespuestaDto<bool>> ResolverAsync(long idJefe, long idOs, bool aprobar, string? comentario, CancellationToken ct);
}
