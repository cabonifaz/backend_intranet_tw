using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerPropuestasCasoDeUso(IPropuestasRepositorio repositorio)
{
    private static readonly string[] Grupos =
        ["todas", "borrador", "por_vb", "en_seguimiento", "aceptada", "rechazada", "cerrada"];

    public Task<RespuestaDto<PropuestasPaginadoDto>> EjecutarAsync(FiltrosPropuestasDto filtros, CancellationToken ct = default)
    {
        if (!string.IsNullOrWhiteSpace(filtros.GrupoEstado)
            && !Grupos.Contains(filtros.GrupoEstado.Trim().ToLowerInvariant()))
        {
            return Task.FromResult(new RespuestaDto<PropuestasPaginadoDto>(1,
                $"Grupo de estado no válido: '{filtros.GrupoEstado}'. Use: {string.Join(", ", Grupos)}."));
        }

        filtros.GrupoEstado = filtros.GrupoEstado?.Trim().ToLowerInvariant();
        filtros.Pagina      = Math.Max(filtros.Pagina, 1);
        filtros.PorPagina   = Math.Clamp(filtros.PorPagina, 1, 100);
        return repositorio.ObtenerPropuestasAsync(filtros, ct);
    }
}
