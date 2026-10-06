using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Equipos del Cliente (HU-88) — sobre la tabla equipo_cliente.</summary>
public class EquiposClienteRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IEquiposClienteRepositorio
{
    public Task<RespuestaDto<EquiposClientePaginadoDto>> ObtenerEquiposAsync(
        string? busqueda, long? idCliente, long? idSede,
        string? clasificacion, string? estado, bool soloVigentesServicio,
        int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerEquiposCliente",
            p =>
            {
                p.AddWithValue("p_busqueda",                Valor(busqueda));
                p.AddWithValue("p_id_cliente",              idCliente ?? 0);
                p.AddWithValue("p_id_sede",                 idSede ?? 0);
                p.AddWithValue("p_clasificacion",           Valor(clasificacion));
                p.AddWithValue("p_estado",                  Valor(estado));
                p.AddWithValue("p_solo_vigentes_servicio",  Bit(soloVigentesServicio));
                p.AddWithValue("p_pagina",                  pagina);
                p.AddWithValue("p_por_pagina",              porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<EquipoClienteListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerListaItem(r));

                int total = await LeerTotalAsync(r, ct);
                return new RespuestaDto<EquiposClientePaginadoDto>(2, mensaje,
                    new EquiposClientePaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<EquipoClienteDetalleDto>> ObtenerEquipoPorIdAsync(long idEquipo, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerEquipoClientePorId",
            p => p.AddWithValue("p_id_equipo", idEquipo),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<EquipoClienteDetalleDto>(1, "Equipo no encontrado.");

                var l = LeerListaItem(r);
                var detalle = new EquipoClienteDetalleDto(
                    l.IdEquipo, l.NumSerie, l.IdCliente, l.ClienteRazonSocial, l.IdSede, l.SedeNombre,
                    l.CodigoCliente, l.CodigoTw, l.Clasificacion, l.ClasificacionLabel, l.Marca, l.Modelo,
                    l.Estado, l.EsActivo,
                    UbicacionEspecifica:    Texto(r, "ubicacion_especifica") ?? "",
                    EsPreRevisado:          Booleano(r, "es_pre_revisado"),
                    UsuarioPreRevisor:      Texto(r, "usuario_pre_revisor") ?? "",
                    FechaPreRevision:       FechaHora(r, "fecha_pre_revision"),
                    BloqueadoParaServicios: Booleano(r, "bloqueado_para_servicios"),
                    IdSuministro:           EnteroLargoNulo(r, "id_suministro"),
                    SuministroLabel:        Texto(r, "suministro_label") ?? "",
                    DivisionMinima:         Texto(r, "division_minima") ?? "",
                    DivisionVerif:          Texto(r, "division_verif") ?? "",
                    DivisionVerifIgual:     Booleano(r, "division_verif_igual"),
                    ClaseExactitud:         Texto(r, "clase_exactitud") ?? "",
                    AlcanceMaximo:          Texto(r, "alcance_maximo") ?? "",
                    EscalaGraduacion:       Texto(r, "escala_graduacion") ?? "",
                    PuntosCalibracion:      Texto(r, "puntos_calibracion") ?? "",
                    RangoOperativoReal:     Texto(r, "rango_operativo_real") ?? "",
                    Material:               Texto(r, "material") ?? "",
                    ValorNominal:           Texto(r, "valor_nominal") ?? "",
                    Observaciones:          Texto(r, "observaciones") ?? "",
                    EstadoOperativo:        Texto(r, "estado_operativo") ?? "",
                    Fotos:                  [],
                    HojaVida:               [],
                    ProximaCalibracion:     "",
                    UsuarioRegistro:        Texto(r, "usuario_registro") ?? "",
                    FechaRegistro:          FechaHora(r, "fecha_registro"),
                    PcRegistro:             Texto(r, "pc_registro") ?? "",
                    FechaModificacion:      FechaHora(r, "fecha_modificacion"));

                return new RespuestaDto<EquipoClienteDetalleDto>(2, mensaje, detalle);
            }, ct);

    public Task<RespuestaDto<long>> GuardarEquipoAsync(GuardarEquipoClienteDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarEquipoCliente",
            p =>
            {
                p.AddWithValue("p_id_equipo",             dto.IdEquipo);
                p.AddWithValue("p_num_serie",             dto.NumSerie!.Trim());
                p.AddWithValue("p_id_cliente",            dto.IdCliente);
                p.AddWithValue("p_id_sede",               dto.IdSede);
                p.AddWithValue("p_codigo_cliente",        Valor(dto.CodigoCliente));
                p.AddWithValue("p_clasificacion",         dto.Clasificacion!);
                p.AddWithValue("p_marca",                 Valor(dto.Marca?.Trim()));
                p.AddWithValue("p_modelo",                Valor(dto.Modelo?.Trim()));
                p.AddWithValue("p_ubicacion_especifica",  Valor(dto.UbicacionEspecifica));
                p.AddWithValue("p_es_pre_revisado",       Bit(dto.EsPreRevisado));
                p.AddWithValue("p_bloqueado_servicios",   Bit(dto.BloqueadoParaServicios));
                p.AddWithValue("p_id_suministro",         dto.IdSuministro ?? 0);
                p.AddWithValue("p_division_minima",       Valor(dto.DivisionMinima));
                p.AddWithValue("p_division_verif",        Valor(dto.DivisionVerif));
                p.AddWithValue("p_division_verif_igual",  Bit(dto.DivisionVerifIgual));
                p.AddWithValue("p_clase_exactitud",       Valor(dto.ClaseExactitud));
                p.AddWithValue("p_alcance_maximo",        Valor(dto.AlcanceMaximo));
                p.AddWithValue("p_escala_graduacion",     Valor(dto.EscalaGraduacion));
                p.AddWithValue("p_puntos_calibracion",    Valor(dto.PuntosCalibracion));
                p.AddWithValue("p_rango_operativo_real",  Valor(dto.RangoOperativoReal));
                p.AddWithValue("p_material",              Valor(dto.Material));
                p.AddWithValue("p_valor_nominal",         Valor(dto.ValorNominal));
                p.AddWithValue("p_observaciones",         Valor(dto.Observaciones));
                p.AddWithValue("p_estado_operativo",      Valor(dto.EstadoOperativo));
                p.AddWithValue("p_es_activo",             Bit(dto.EsActivo));
                p.AddWithValue("p_guardar_como_borrador", Bit(dto.GuardarComoBorrador));
                p.AddWithValue("p_id_usuario",            idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_equipo") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            }, ct);

    public Task<RespuestaDto<object>> CambiarEstadoEquipoAsync(long idEquipo, string estado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoEquipoCliente",
            p =>
            {
                p.AddWithValue("p_id_equipo",  idEquipo);
                p.AddWithValue("p_estado",     estado);
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    private static EquipoClienteListaItemDto LeerListaItem(MySqlDataReader r) => new(
        IdEquipo:           EnteroLargo(r, "id_equipo"),
        NumSerie:           Texto(r, "num_serie") ?? "",
        IdCliente:          EnteroLargo(r, "id_cliente"),
        ClienteRazonSocial: Texto(r, "cliente_razon_social") ?? "",
        IdSede:             EnteroLargo(r, "id_sede"),
        SedeNombre:         Texto(r, "sede_nombre") ?? "",
        CodigoCliente:      Texto(r, "codigo_cliente") ?? "",
        CodigoTw:           Texto(r, "codigo_tw") ?? "",
        Clasificacion:      Texto(r, "clasificacion") ?? "",
        ClasificacionLabel: Texto(r, "clasificacion_label") ?? "",
        Marca:              Texto(r, "marca") ?? "",
        Modelo:             Texto(r, "modelo") ?? "",
        Estado:             Texto(r, "estado") ?? "",
        EsActivo:           Booleano(r, "es_activo"));
}
