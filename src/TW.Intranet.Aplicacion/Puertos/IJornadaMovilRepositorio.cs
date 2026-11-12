using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>App Mobile HU-20 — Reloj marcador de jornada.</summary>
public interface IJornadaMovilRepositorio
{
    Task<RespuestaDto<JornadaMovilDto>> ObtenerAsync(long idUsuario, CancellationToken ct);

    Task<RespuestaDto<MarcacionRegistradaDto>> MarcarAsync(
        long idUsuario, string tipo, decimal latitud, decimal longitud, decimal? precisionMetros, DateTime? marcadoUtc, bool sinConexion, CancellationToken ct);

    Task<RespuestaDto<UbicacionRegistradaDto>> RegistrarUbicacionAsync(
        long idUsuario, decimal latitud, decimal longitud, decimal? precisionMetros, decimal? velocidadKmh, decimal? altitudM, CancellationToken ct);
}
