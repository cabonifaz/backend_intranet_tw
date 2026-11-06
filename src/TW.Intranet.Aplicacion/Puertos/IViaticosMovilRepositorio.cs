using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Viáticos y gastos del técnico de la app móvil (App Mobile HU-25 / HU-26).</summary>
public interface IViaticosMovilRepositorio
{
    Task<RespuestaDto<ViaticosMovilDto>> ObtenerAsync(long idUsuario, CancellationToken ct);
}
