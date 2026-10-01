using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Alta de valores en catálogos de tabla_maestra (HU-86).</summary>
public class CatalogosRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ICatalogosRepositorio
{
    public Task<RespuestaDto<CatalogoItemDto>> AgregarItemAsync(
        string descripcion, string etiqueta, string codigo, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AgregarItemCatalogo",
            p =>
            {
                p.AddWithValue("p_descripcion", descripcion);
                p.AddWithValue("p_string1",     etiqueta);
                p.AddWithValue("p_string2",     codigo);
                p.AddWithValue("p_id_usuario",  idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CatalogoItemDto>(3, "El procedimiento no devolvió el ítem creado.");

                var item = new CatalogoItemDto(
                    Entero(r, "id"),
                    Texto(r, "nombre") ?? "",
                    Texto(r, "codigo"));

                return new RespuestaDto<CatalogoItemDto>(2, mensaje, item);
            }, ct);
}
