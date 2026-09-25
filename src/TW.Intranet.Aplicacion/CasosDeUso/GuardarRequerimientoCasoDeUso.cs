using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarRequerimientoCasoDeUso(ICrmRepositorio repo)
{
    public Task<RespuestaDto<long>> EjecutarAsync(
        GuardarRequerimientoComandoDto comando, long idUsuario, CancellationToken ct)
        => repo.GuardarRequerimientoAsync(comando, idUsuario, ct);
}
