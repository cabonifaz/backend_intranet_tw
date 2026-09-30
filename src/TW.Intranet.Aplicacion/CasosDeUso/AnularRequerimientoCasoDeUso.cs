using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class AnularRequerimientoCasoDeUso(ICrmRepositorio repo)
{
    public Task<RespuestaDto<long>> EjecutarAsync(
        long idRequerimiento, AnularRequerimientoComandoDto comando, long idUsuario, string rol, CancellationToken ct)
        => repo.AnularRequerimientoAsync(idRequerimiento, comando, idUsuario, rol, ct);
}
