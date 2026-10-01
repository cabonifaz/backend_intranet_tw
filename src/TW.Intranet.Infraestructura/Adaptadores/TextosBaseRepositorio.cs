using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Textos base (HU-85).</summary>
public class TextosBaseRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ITextosBaseRepositorio
{
    public Task<RespuestaDto<TextosBasePaginadoDto>> ObtenerTextosBaseAsync(
        string? busqueda, string? tipoCategoria, string? estado, bool soloPredeterminados,
        int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerTextosBase",
            p =>
            {
                p.AddWithValue("p_busqueda",             Valor(busqueda));
                p.AddWithValue("p_tipo_categoria",       Valor(tipoCategoria));
                p.AddWithValue("p_estado",               Valor(estado));
                p.AddWithValue("p_solo_predeterminados", Bit(soloPredeterminados));
                p.AddWithValue("p_pagina",               pagina);
                p.AddWithValue("p_por_pagina",           porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<TextoBaseListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerListaItem(r));

                int total = await LeerTotalAsync(r, ct);
                return new RespuestaDto<TextosBasePaginadoDto>(2, mensaje,
                    new TextosBasePaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<TextoBaseDetalleDto>> ObtenerTextoBasePorIdAsync(long idTextoBase, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerTextoBasePorId",
            p => p.AddWithValue("p_id_texto_base", idTextoBase),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<TextoBaseDetalleDto>(1, "Texto base no encontrado.");

                var l = LeerListaItem(r);
                var detalle = new TextoBaseDetalleDto(
                    l.IdTextoBase, l.CodigoCorto, l.TipoCategoria, l.TipoCategoriaLabel,
                    l.Nombre, l.TextoClausula, l.Estado, l.EsPredeterminado, l.EsNegritaPorDefecto,
                    l.FechaCreacion, l.UsuarioCreador,
                    SeccionDossier:             Texto(r, "seccion_dossier"),
                    OrdenAparicion:             Entero(r, "orden_aparicion"),
                    NivelSangria:               Texto(r, "nivel_sangria") ?? "estandar",
                    AplicaTodosServicios:       Booleano(r, "aplica_todos_servicios"),
                    AplicaCalibracionLab:       Booleano(r, "aplica_calibracion_lab"),
                    AplicaCalibracionPlanta:    Booleano(r, "aplica_calibracion_planta"),
                    AplicaMantenimiento:        Booleano(r, "aplica_mantenimiento"),
                    AplicaVentaSuministros:     Booleano(r, "aplica_venta_suministros"),
                    VisibleGestoresComerciales: Booleano(r, "visible_gestores_comerciales"),
                    VisibleTecnicosMetrologos:  Booleano(r, "visible_tecnicos_metrologos"),
                    VisibleSupervisores:        Booleano(r, "visible_supervisores"),
                    Version:                    Entero(r, "version"),
                    PropuestasAsociadas:        Entero(r, "propuestas_asociadas"));

                return new RespuestaDto<TextoBaseDetalleDto>(2, mensaje, detalle);
            }, ct);

    public Task<RespuestaDto<long>> GuardarTextoBaseAsync(GuardarTextoBaseDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarTextoBase",
            p =>
            {
                p.AddWithValue("p_id_texto_base",                dto.IdTextoBase);
                p.AddWithValue("p_codigo_corto",                 dto.CodigoCorto!);
                p.AddWithValue("p_tipo_categoria",               dto.TipoCategoria!.Trim());
                p.AddWithValue("p_nombre",                       dto.Nombre!.Trim());
                p.AddWithValue("p_texto_clausula",               dto.TextoClausula!);
                p.AddWithValue("p_seccion_dossier",              Valor(dto.SeccionDossier));
                p.AddWithValue("p_orden_aparicion",              dto.OrdenAparicion);
                p.AddWithValue("p_nivel_sangria",                string.IsNullOrWhiteSpace(dto.NivelSangria) ? "estandar" : dto.NivelSangria);
                p.AddWithValue("p_es_predeterminado",            Bit(dto.EsPredeterminado));
                p.AddWithValue("p_es_negrita_por_defecto",       Bit(dto.EsNegritaPorDefecto));
                p.AddWithValue("p_activo",                       Bit(dto.Activo));
                p.AddWithValue("p_aplica_todos_servicios",       Bit(dto.AplicaTodosServicios));
                p.AddWithValue("p_aplica_calibracion_lab",       Bit(dto.AplicaCalibracionLab));
                p.AddWithValue("p_aplica_calibracion_planta",    Bit(dto.AplicaCalibracionPlanta));
                p.AddWithValue("p_aplica_mantenimiento",         Bit(dto.AplicaMantenimiento));
                p.AddWithValue("p_aplica_venta_suministros",     Bit(dto.AplicaVentaSuministros));
                p.AddWithValue("p_visible_gestores_comerciales", Bit(dto.VisibleGestoresComerciales));
                p.AddWithValue("p_visible_tecnicos_metrologos",  Bit(dto.VisibleTecnicosMetrologos));
                p.AddWithValue("p_visible_supervisores",         Bit(dto.VisibleSupervisores));
                p.AddWithValue("p_guardar_como_borrador",        Bit(dto.GuardarComoBorrador));
                p.AddWithValue("p_id_usuario",                   idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_texto_base") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            }, ct);

    public Task<RespuestaDto<object>> CambiarEstadoTextoBaseAsync(
        long idTextoBase, string estado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoTextoBase",
            p =>
            {
                p.AddWithValue("p_id_texto_base", idTextoBase);
                p.AddWithValue("p_estado",        estado);
                p.AddWithValue("p_id_usuario",    idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    private static TextoBaseListaItemDto LeerListaItem(MySqlDataReader r) => new(
        IdTextoBase:         EnteroLargo(r, "id_texto_base"),
        CodigoCorto:         Texto(r, "codigo_corto") ?? "",
        TipoCategoria:       Texto(r, "tipo_categoria") ?? "",
        TipoCategoriaLabel:  Texto(r, "tipo_categoria_label") ?? "",
        Nombre:              Texto(r, "nombre") ?? "",
        TextoClausula:       Texto(r, "texto_clausula") ?? "",
        Estado:              Texto(r, "estado") ?? "",
        EsPredeterminado:    Booleano(r, "es_predeterminado"),
        EsNegritaPorDefecto: Booleano(r, "es_negrita_por_defecto"),
        FechaCreacion:       FechaHora(r, "fecha_creacion"),
        UsuarioCreador:      Texto(r, "usuario_creador") ?? "");
}
