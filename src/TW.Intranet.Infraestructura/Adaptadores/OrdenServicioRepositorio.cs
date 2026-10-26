using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Módulo Órdenes de Servicio / Metrología (OS / OM).</summary>
public class OrdenServicioRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IOrdenServicioRepositorio
{
    private static int Ent(MySqlDataReader r, string c) => EsNulo(r, c) ? 0 : Convert.ToInt32(r[c]);

    // ══════════════════════ HU-41 Bandeja ══════════════════════

    public Task<RespuestaDto<BandejaOrdenesServicioDto>> ObtenerBandejaAsync(
        FiltrosBandejaOrdenesServicioDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaOrdenesServicio",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_estado",         Valor(f.Estado));
                p.AddWithValue("p_tipo",           Valor(f.Tipo));
                p.AddWithValue("p_id_cliente",     Valor(f.IdCliente));
                p.AddWithValue("p_id_responsable", Valor(f.IdResponsable));
                p.AddWithValue("p_fecha_desde",    Valor(f.FechaDesde?.Date));
                p.AddWithValue("p_fecha_hasta",    Valor(f.FechaHasta?.Date));
                p.AddWithValue("p_busqueda",       Valor(f.Busqueda));
                p.AddWithValue("p_pagina",         f.Pagina);
                p.AddWithValue("p_por_pagina",     f.PorPagina);
                p.AddWithValue("p_exportar",       Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = new TarjetasOrdenesServicioDto(0, 0, 0, 0, 0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    tarjetas = new TarjetasOrdenesServicioDto(
                        Ent(r, "total"), Ent(r, "borradores"), Ent(r, "emitidas"), Ent(r, "emitidas_semana"),
                        Ent(r, "programadas"), Ent(r, "en_ejecucion"), Ent(r, "finalizadas"), Ent(r, "finalizadas_mes"),
                        Ent(r, "anuladas"));

                await r.NextResultAsync(ct);
                var items = new List<ItemBandejaOrdenServicioDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new ItemBandejaOrdenServicioDto
                    {
                        IdOs                   = EnteroLargo(r, "id_os"),
                        Tipo                   = Texto(r, "tipo") ?? "OS",
                        Numero                 = Texto(r, "numero") ?? "",
                        Estado                 = Texto(r, "estado") ?? "",
                        EstadoGrupo            = Texto(r, "estado_grupo") ?? "",
                        EstadoLabel            = Texto(r, "estado_label") ?? "",
                        FechaEmision           = FechaHora(r, "fecha_emision"),
                        Emitida                = Booleano(r, "emitida_registrada"),
                        IdCliente              = EnteroLargoNulo(r, "id_cliente"),
                        RazonSocial            = Texto(r, "razon_social"),
                        Ruc                    = Texto(r, "ruc"),
                        IdPropuesta            = EnteroLargoNulo(r, "id_propuesta"),
                        NumeroPropuesta        = Texto(r, "numero_propuesta"),
                        VersionPropuesta       = EnteroNulo(r, "version_propuesta"),
                        IdExpediente           = EnteroLargoNulo(r, "id_expediente"),
                        IdResponsable          = EnteroLargoNulo(r, "id_responsable"),
                        Responsable            = Texto(r, "responsable"),
                        NumeroEquipos          = Ent(r, "n_equipos"),
                        NumeroConceptos        = Ent(r, "n_conceptos"),
                        SolicitudPendiente     = Booleano(r, "solicitud_pendiente"),
                        IdSolicitudPendiente   = EnteroLargoNulo(r, "id_solicitud_pendiente"),
                        EdicionAprobada        = Booleano(r, "edicion_aprobada"),
                        PuedeEditar            = Booleano(r, "puede_editar"),
                        PuedeSolicitarEdicion  = Booleano(r, "puede_solicitar_edicion"),
                        PuedeResolverSolicitud = Booleano(r, "puede_resolver_solicitud"),
                        PuedeAnular            = Booleano(r, "puede_anular"),
                    });

                await r.NextResultAsync(ct);
                var total = await r.ReadAsync(ct) ? Ent(r, "total") : 0;

                var clientes = await LeerOpcionesAsync(r, ct);
                var responsables = await LeerOpcionesAsync(r, ct);

                return new RespuestaDto<BandejaOrdenesServicioDto>(2, mensaje,
                    new BandejaOrdenesServicioDto(tarjetas, items, total, exportar ? 1 : f.Pagina, exportar ? total : f.PorPagina,
                                                  clientes, responsables));
            },
            ct);

    private static async Task<List<OpcionFiltroDto>> LeerOpcionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<OpcionFiltroDto>();
        await r.NextResultAsync(ct);
        while (await r.ReadAsync(ct))
            lista.Add(new OpcionFiltroDto(EnteroLargo(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return lista;
    }
}
