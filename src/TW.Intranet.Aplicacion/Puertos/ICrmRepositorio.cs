using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface ICrmRepositorio
{
    Task<RespuestaDto<RequerimientosPaginadoDto>> ObtenerRequerimientosAsync(
        string? estado, string? busqueda, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<CatalogosRequerimientoDto>> ObtenerCatalogosAsync(CancellationToken ct);

    Task<RespuestaDto<RequerimientoFichaDto>> ObtenerRequerimientoPorIdAsync(
        long idRequerimiento, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarRequerimientoAsync(
        GuardarRequerimientoComandoDto comando, long idUsuario, CancellationToken ct);
}
