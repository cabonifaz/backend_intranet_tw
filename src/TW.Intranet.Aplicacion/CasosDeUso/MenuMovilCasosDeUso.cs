using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// App Mobile HU-02 — Indicadores del menú principal del técnico:
/// servicios asignados, servicios de hoy (Ruta del Día) y el próximo servicio.
/// </summary>
public class ObtenerResumenMenuMovilCasoDeUso(IMenuMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ResumenMenuMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<ResumenMenuMovilDto>(1, "No se pudo identificar al usuario."));

        return repositorio.ObtenerResumenAsync(idUsuario, ct);
    }
}
