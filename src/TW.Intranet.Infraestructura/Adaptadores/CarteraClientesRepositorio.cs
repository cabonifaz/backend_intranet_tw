using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class CarteraClientesRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ICarteraClientesRepositorio
{
    public Task<RespuestaDto<CarteraClientesDto>> ObtenerAsync(FiltrosCarteraClientesDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCarteraClientes",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_comercial", Valor(f.IdComercial));
                p.AddWithValue("p_busqueda",     Valor(f.Busqueda));
                p.AddWithValue("p_asignacion",   Valor(f.Asignacion));
                p.AddWithValue("p_pagina",       f.Pagina);
                p.AddWithValue("p_por_pagina",   f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<ClienteCarteraDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ClienteCarteraDto(
                        EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "ruc"), Texto(r, "estado"),
                        EnteroLargoNulo(r, "id_comercial"), Texto(r, "comercial"),
                        FechaHora(r, "asignado_en"), Texto(r, "asignado_por")));

                int total = await LeerTotalAsync(r, ct);

                await r.NextResultAsync(ct);
                var comerciales = new List<ComercialCarteraDto>();
                while (await r.ReadAsync(ct))
                    comerciales.Add(new ComercialCarteraDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "cargo"), Entero(r, "clientes")));

                await r.NextResultAsync(ct);
                bool puedeAsignar = await r.ReadAsync(ct) && Booleano(r, "puede_asignar");

                int porPagina = f.PorPagina is >= 1 and <= 500 ? f.PorPagina : 20;
                return new RespuestaDto<CarteraClientesDto>(2, mensaje,
                    new CarteraClientesDto(items, total, Math.Max(f.Pagina, 1), porPagina, comerciales, puedeAsignar));
            },
            ct);

    public Task<RespuestaDto<int>> AsignarAsync(AsignarCarteraClientesComandoDto c, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_AsignarCarteraClientes",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_comercial",  c.IdComercial is > 0 ? (object)c.IdComercial.Value : DBNull.Value);
                p.AddWithValue("p_ids_clientes",  JsonSerializer.Serialize(c.IdsClientes));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                int n = await r.ReadAsync(ct) ? Entero(r, "clientes") : 0;
                return new RespuestaDto<int>(2, mensaje, n);
            },
            ct);
}
