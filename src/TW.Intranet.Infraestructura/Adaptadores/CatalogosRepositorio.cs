using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Alta de valores en catálogos de tabla_maestra (HU-86).</summary>
public class CatalogosRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ICatalogosRepositorio
{
    public Task<RespuestaDto<CatalogoItemDto>> AgregarItemAsync(
        string descripcion, string etiqueta, string codigo, string? string3, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AgregarItemCatalogo",
            p =>
            {
                p.AddWithValue("p_descripcion", descripcion);
                p.AddWithValue("p_string1",     etiqueta);
                p.AddWithValue("p_string2",     codigo);
                p.AddWithValue("p_string3",     Valor(string3));
                p.AddWithValue("p_id_usuario",  idUsuario);
            },
            (r, mensaje) => LeerItemAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<CatalogoItemDto>> EditarItemAsync(
        string descripcion, string codigo, string etiqueta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_EditarItemCatalogo",
            p =>
            {
                p.AddWithValue("p_descripcion", descripcion);
                p.AddWithValue("p_codigo",      codigo);
                p.AddWithValue("p_string1",     etiqueta);
                p.AddWithValue("p_id_usuario",  idUsuario);
            },
            (r, mensaje) => LeerItemAsync(r, mensaje, ct), ct);

    private static async Task<RespuestaDto<CatalogoItemDto>> LeerItemAsync(
        MySqlConnector.MySqlDataReader r, string mensaje, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        if (!await r.ReadAsync(ct))
            return new RespuestaDto<CatalogoItemDto>(3, "El procedimiento no devolvió el ítem.");

        var item = new CatalogoItemDto(
            Entero(r, "id"),
            Texto(r, "nombre") ?? "",
            Texto(r, "codigo"),
            String3: Texto(r, "string3"));

        return new RespuestaDto<CatalogoItemDto>(2, mensaje, item);
    }
}
