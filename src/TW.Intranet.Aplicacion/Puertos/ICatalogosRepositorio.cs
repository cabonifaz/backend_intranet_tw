using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface ICatalogosRepositorio
{
    Task<RespuestaDto<CatalogoItemDto>> AgregarItemAsync(
        string descripcion, string etiqueta, string codigo, long idUsuario, CancellationToken ct);
}
