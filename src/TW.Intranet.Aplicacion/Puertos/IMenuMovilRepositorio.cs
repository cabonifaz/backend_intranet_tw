using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Datos del menú principal de la app móvil (App Mobile HU-02).</summary>
public interface IMenuMovilRepositorio
{
    Task<RespuestaDto<ResumenMenuMovilDto>> ObtenerResumenAsync(long idUsuario, CancellationToken ct);
}
