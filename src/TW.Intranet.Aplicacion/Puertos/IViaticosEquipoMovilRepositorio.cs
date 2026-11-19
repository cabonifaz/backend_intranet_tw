using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Viáticos y gastos del equipo del Jefe de Área en la app móvil (App Mobile HU-35). Todo sale de procedimientos almacenados.</summary>
public interface IViaticosEquipoMovilRepositorio
{
    Task<RespuestaDto<ViaticosEquipoDto>> ObtenerAsync(long idUsuario, CancellationToken ct);

    Task<RespuestaDto<ViaticoServicioDto>> ObtenerServicioAsync(long idUsuario, long idOs, CancellationToken ct);

    /// <summary>Asigna el viático (montos ya normalizados a 2 decimales) a un técnico del servicio; depositado = lo deja marcado como depositado.</summary>
    Task<RespuestaDto<AsignacionViaticoResultadoDto>> AsignarAsync(long idUsuario, long idOs, long idTecnico, decimal movilidad, decimal alimentacion, decimal alojamiento, decimal otros,
                                                                   bool depositado, string version, CancellationToken ct);
}
