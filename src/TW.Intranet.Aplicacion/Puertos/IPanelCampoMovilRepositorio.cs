using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Panel de campo y seguimiento del servicio del Jefe de Área en la app móvil (App Mobile HU-29 / HU-30).</summary>
public interface IPanelCampoMovilRepositorio
{
    Task<RespuestaDto<PanelCampoDto>> ObtenerPanelAsync(long idUsuario, CancellationToken ct);

    Task<RespuestaDto<ServiciosJefaturaDto>> ObtenerServiciosAsync(long idUsuario, string filtro, string? busqueda, CancellationToken ct);

    Task<RespuestaDto<ServicioJefaturaDto>> ObtenerServicioAsync(long idUsuario, long idOs, CancellationToken ct);

    Task<RespuestaDto<RutaServicioDto>> ObtenerRutaAsync(long idUsuario, long idOs, CancellationToken ct);

    /// <summary>Cambio manual de estado (modo cambio_estado) o constancia del aviso al cliente (modo aviso_cliente).</summary>
    Task<RespuestaDto<RegistroSeguimientoResultadoDto>> RegistrarAsync(long idUsuario, long idOs, string modo, string? nuevoEstado, int? idMotivo, string texto, CancellationToken ct);
}
