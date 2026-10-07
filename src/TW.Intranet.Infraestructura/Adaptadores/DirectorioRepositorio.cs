using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Directorio interno (#4303) y valores existentes para evitar duplicados (#4290).</summary>
public class DirectorioRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IDirectorioRepositorio
{
    public Task<RespuestaDto<DirectorioPaginadoDto>> ObtenerDirectorioAsync(
        string? busqueda, string? area, int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDirectorio",
            p =>
            {
                p.AddWithValue("p_busqueda",   Valor(busqueda));
                p.AddWithValue("p_area",       Valor(area));
                p.AddWithValue("p_pagina",     pagina);
                p.AddWithValue("p_por_pagina", porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<DirectorioItemDto>();
                while (await r.ReadAsync(ct))
                {
                    var anexo   = Texto(r, "anexo") ?? "";
                    var troncal = Texto(r, "troncal") ?? "";
                    items.Add(new DirectorioItemDto(
                        EnteroLargo(r, "id_usuario"),
                        Texto(r, "nombre_completo") ?? "",
                        Texto(r, "area") ?? "",
                        Texto(r, "area_label") ?? "",
                        Texto(r, "cargo") ?? "",
                        Texto(r, "correo") ?? "",
                        Texto(r, "telefono") ?? "",
                        anexo,
                        troncal,
                        anexo == "" ? "" : (troncal == "" ? anexo : $"{troncal} - {anexo}"),
                        Texto(r, "cumpleanos") ?? ""));
                }
                int total = await LeerTotalAsync(r, ct);
                return new RespuestaDto<DirectorioPaginadoDto>(2, mensaje,
                    new DirectorioPaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<List<CumpleanosItemDto>>> ObtenerCumpleanosAsync(int mes, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCumpleanos",
            p => p.AddWithValue("p_mes", mes),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<CumpleanosItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new CumpleanosItemDto(
                        EnteroLargo(r, "id_usuario"),
                        Texto(r, "nombre_completo") ?? "",
                        Texto(r, "area_label") ?? "",
                        (int)EnteroLargo(r, "dia"),
                        Texto(r, "cumpleanos") ?? ""));
                return new RespuestaDto<List<CumpleanosItemDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<List<ValorExistenteDto>>> ObtenerValoresExistentesAsync(string campo, long? idCliente, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerValoresExistentes",
            p =>
            {
                p.AddWithValue("p_campo",      campo);
                p.AddWithValue("p_id_cliente", Valor(idCliente));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<ValorExistenteDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ValorExistenteDto(
                        Texto(r, "valor") ?? "",
                        Texto(r, "detalle") ?? "",
                        (int)EnteroLargo(r, "usos")));
                return new RespuestaDto<List<ValorExistenteDto>>(2, mensaje, items);
            }, ct);
}
