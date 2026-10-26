using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Módulo Órdenes de Servicio / Metrología (OS / OM).</summary>
public interface IOrdenServicioRepositorio
{
    /// <summary>HU-41 Bandeja. exportar = true: todas las filas, sin paginar.</summary>
    Task<RespuestaDto<BandejaOrdenesServicioDto>> ObtenerBandejaAsync(
        FiltrosBandejaOrdenesServicioDto filtros, bool exportar, long idUsuario, CancellationToken ct);
}
