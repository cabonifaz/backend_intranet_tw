using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IDirectorioRepositorio
{
    Task<RespuestaDto<DirectorioPaginadoDto>> ObtenerDirectorioAsync(string? busqueda, string? area, int pagina, int porPagina, CancellationToken ct);
    Task<RespuestaDto<List<CumpleanosItemDto>>> ObtenerCumpleanosAsync(int mes, CancellationToken ct);
    Task<RespuestaDto<List<ValorExistenteDto>>> ObtenerValoresExistentesAsync(string campo, long? idCliente, CancellationToken ct);
}
