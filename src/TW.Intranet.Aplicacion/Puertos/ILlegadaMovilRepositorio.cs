using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Registro de llegada con validación GPS de la app móvil (App Mobile HU-06).</summary>
public interface ILlegadaMovilRepositorio
{
    Task<RespuestaDto<LlegadaMovilDto>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct);

    Task<RespuestaDto<ValidacionLlegadaMovilDto>> ValidarAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal precisionMetros, CancellationToken ct);

    /// <summary>capturadoUtc: hora (UTC, sin zona) en que el técnico confirmó en el teléfono; null = la hora del servidor.</summary>
    Task<RespuestaDto<ResultadoLlegadaMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal precisionMetros, DateTime? capturadoUtc, CancellationToken ct);
}
