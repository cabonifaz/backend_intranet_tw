using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>Devuelve los datos actuales del usuario autenticado (nombre, rol, área, etc.).
/// El front lo usa para refrescar su sesión local sin forzar un re-login cuando el admin
/// cambia atributos del usuario (rol o área).</summary>
public class ObtenerMisDatosCasoDeUso(IAutenticacionRepositorio repositorio)
{
    public Task<RespuestaDto<MisDatosDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<MisDatosDto>(1, "Sesión no válida."))
            : repositorio.ObtenerMisDatosAsync(idUsuario, ct);
}
