using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Lista de objetivos y selección de equipos de la app móvil (App Mobile HU-07).</summary>
public interface IObjetivosMovilRepositorio
{
    /// <summary>Objetivos de la OS (con el Hard Stop de la llegada). buscar filtra solo la lista de equipos.</summary>
    Task<RespuestaDto<ObjetivosMovilDto>> ObtenerAsync(long idUsuario, long idOs, string buscar, CancellationToken ct);

    /// <summary>Equipo de la OS cuyo N/S, código del cliente o COD TW coincide con lo escaneado.</summary>
    Task<RespuestaDto<ObjetivoEquipoMovilDto>> BuscarPorQrAsync(long idUsuario, long idOs, string codigo, CancellationToken ct);

    /// <summary>accion: iniciar | pausar | reanudar. capturadoUtc: hora (UTC, sin zona) en que el técnico tocó el botón; null = la del servidor.</summary>
    Task<RespuestaDto<ResultadoCambioEstadoEquipoMovilDto>> CambiarEstadoAsync(
        long idUsuario, long idOs, long idOsEquipo, string accion, string? motivo, DateTime? capturadoUtc, CancellationToken ct);

    Task<RespuestaDto<OpcionesEquipoNuevoMovilDto>> ObtenerOpcionesEquipoNuevoAsync(long idUsuario, long idOs, CancellationToken ct);

    /// <summary>rutaFoto: foto de la placa ya guardada en el almacenamiento de archivos.</summary>
    Task<RespuestaDto<ResultadoEquipoNuevoMovilDto>> RegistrarEquipoNuevoAsync(
        long idUsuario, long idOs, NuevoEquipoMovilDto equipo, string rutaFoto, CancellationToken ct);
}
