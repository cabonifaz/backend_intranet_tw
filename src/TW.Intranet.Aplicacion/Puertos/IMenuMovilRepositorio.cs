using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Datos del menú principal de la app móvil (App Mobile HU-02).</summary>
public interface IMenuMovilRepositorio
{
    Task<RespuestaDto<ResumenMenuMovilDto>> ObtenerResumenAsync(long idUsuario, CancellationToken ct);

    /// <summary>Menú de Jefatura (HU-28): resumen del día del área del Jefe de Servicio Técnico / Metrología.</summary>
    Task<RespuestaDto<MenuJefaturaMovilDto>> ObtenerMenuJefaturaAsync(long idUsuario, CancellationToken ct);
}
