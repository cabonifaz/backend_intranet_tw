using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface ICatalogosRepositorio
{
    Task<RespuestaDto<CatalogoItemDto>> AgregarItemAsync(
        string descripcion, string etiqueta, string codigo, string? string3, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<CatalogoItemDto>> EditarItemAsync(
        string descripcion, string codigo, string etiqueta, long idUsuario, CancellationToken ct);
}
