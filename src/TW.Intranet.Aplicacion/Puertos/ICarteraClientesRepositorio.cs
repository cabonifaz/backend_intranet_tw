using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface ICarteraClientesRepositorio
{
    Task<RespuestaDto<CarteraClientesDto>> ObtenerAsync(FiltrosCarteraClientesDto filtros, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<int>> AsignarAsync(AsignarCarteraClientesComandoDto comando, long idUsuario, CancellationToken ct);
}
