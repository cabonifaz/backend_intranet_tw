using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>Sección 05 de la ficha: "Suplentes que lo cubren" (titular) y "Personas a las que suple" (suplente).</summary>
public class ObtenerSuplenciasPorUsuarioCasoDeUso(IUsuariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<SuplenteListaItemDto>>> EjecutarAsync(
        long idUsuario, string perspectiva, CancellationToken ct = default)
        => repositorio.ObtenerSuplenciasPorUsuarioAsync(idUsuario, perspectiva, ct);
}
