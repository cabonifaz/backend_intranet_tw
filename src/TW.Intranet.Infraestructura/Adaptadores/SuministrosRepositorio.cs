using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Suministros (HU-86) — sobre la tabla catalogo_item.</summary>
public class SuministrosRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ISuministrosRepositorio
{
    private const string NivelEstandar    = "estandar";
    private const string NivelVolumen     = "volumen";
    private const string NivelCorporativo = "corporativo_alto";

    public Task<RespuestaDto<SuministrosPaginadoDto>> ObtenerSuministrosAsync(
        string? busqueda, string? clase, string? tipo, string? estado, bool soloEnPropuestas, bool excluirServicios,
        int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSuministros",
            p =>
            {
                p.AddWithValue("p_busqueda",           Valor(busqueda));
                p.AddWithValue("p_clase",              Valor(clase));
                p.AddWithValue("p_tipo",               Valor(tipo));
                p.AddWithValue("p_estado",             Valor(estado));
                p.AddWithValue("p_solo_en_propuestas", Bit(soloEnPropuestas));
                p.AddWithValue("p_excluir_servicios",  Bit(excluirServicios));
                p.AddWithValue("p_pagina",             pagina);
                p.AddWithValue("p_por_pagina",         porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<SuministroListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerListaItem(r));

                int total = await LeerTotalAsync(r, ct);
                return new RespuestaDto<SuministrosPaginadoDto>(2, mensaje,
                    new SuministrosPaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<SuministroDetalleDto>> ObtenerSuministroPorIdAsync(long idSuministro, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSuministroPorId",
            p => p.AddWithValue("p_id_suministro", idSuministro),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<SuministroDetalleDto>(1, "Suministro no encontrado.");

                var l = LeerListaItem(r);
                var escalas = new List<EscalaTarifaDto>
                {
                    new(NivelEstandar,    DecimalNulo(r, "precio_nivel_estandar")),
                    new(NivelVolumen,     DecimalNulo(r, "precio_nivel_volumen")),
                    new(NivelCorporativo, DecimalNulo(r, "precio_nivel_corporativo")),
                };

                var detalle = new SuministroDetalleDto(
                    l.IdSuministro, l.Codigo, l.Clase, l.ClaseLabel, l.Tipo, l.TipoLabel,
                    l.Subtipo, l.SubtipoLabel, l.Descripcion, l.Marca, l.Modelo, l.CtaContable,
                    l.Procedencia, l.ProcedenciaLabel, l.Estado, l.EsActivoEnCatalogo, l.UsarEnPropuestas,
                    DescripcionAuto:        Texto(r, "descripcion_auto") ?? "",
                    DescripcionManual:      Texto(r, "descripcion_manual") ?? "",
                    Alcance:                Texto(r, "alcance") ?? "",
                    PrecioMinReferencia:    DecimalNulo(r, "precio_min_referencia"),
                    Escalas:                escalas,
                    AplicaServicio:         Booleano(r, "aplica_servicio"),
                    AplicaMetrologia:       Booleano(r, "aplica_metrologia"),
                    IdPrimerProcedimiento:  Texto(r, "id_primer_procedimiento"),
                    IdSegundoProcedimiento: Texto(r, "id_segundo_procedimiento"),
                    UsuarioRegistro:        Texto(r, "usuario_registro") ?? "",
                    FechaRegistro:          FechaHora(r, "fecha_registro"),
                    FechaModificacion:      FechaHora(r, "fecha_modificacion"),
                    TotalEdiciones:         Entero(r, "total_ediciones"),
                    FirmaDigital:           Texto(r, "firma_digital") ?? "",
                    UrlFoto:                Texto(r, "url_foto") ?? "",
                    UrlManualPdf:           Texto(r, "url_manual_pdf") ?? "");

                return new RespuestaDto<SuministroDetalleDto>(2, mensaje, detalle);
            }, ct);

    public Task<RespuestaDto<long>> GuardarSuministroAsync(GuardarSuministroDto dto, long idUsuario, CancellationToken ct)
    {
        decimal? Precio(string nivel) =>
            dto.Escalas?.FirstOrDefault(e => string.Equals(e.Nivel, nivel, StringComparison.OrdinalIgnoreCase))?.Precio;

        return EjecutarAsync("SP_GuardarSuministro",
            p =>
            {
                p.AddWithValue("p_id_suministro",            dto.IdSuministro);
                p.AddWithValue("p_clase",                    dto.Clase!);
                p.AddWithValue("p_tipo",                     dto.Tipo!.Trim());
                p.AddWithValue("p_subtipo",                  dto.Subtipo!.Trim());
                p.AddWithValue("p_marca",                    Valor(dto.Marca));
                p.AddWithValue("p_modelo",                   Valor(dto.Modelo));
                p.AddWithValue("p_descripcion_auto",         dto.DescripcionAuto!.Trim());
                p.AddWithValue("p_descripcion_manual",       Valor(dto.DescripcionManual));
                p.AddWithValue("p_alcance",                  Valor(dto.Alcance));
                p.AddWithValue("p_cta_contable",             Valor(dto.CtaContable));
                p.AddWithValue("p_procedencia",              Valor(dto.Procedencia));
                p.AddWithValue("p_activo",                   Bit(dto.EsActivoEnCatalogo));
                p.AddWithValue("p_usar_en_propuestas",       Bit(dto.UsarEnPropuestas));
                p.AddWithValue("p_precio_min_referencia",    Valor(dto.PrecioMinReferencia));
                p.AddWithValue("p_precio_nivel_estandar",    Valor(Precio(NivelEstandar)));
                p.AddWithValue("p_precio_nivel_volumen",     Valor(Precio(NivelVolumen)));
                p.AddWithValue("p_precio_nivel_corporativo", Valor(Precio(NivelCorporativo)));
                p.AddWithValue("p_aplica_servicio",          Bit(dto.AplicaServicio));
                p.AddWithValue("p_aplica_metrologia",        Bit(dto.AplicaMetrologia));
                p.AddWithValue("p_id_primer_procedimiento",  Valor(dto.IdPrimerProcedimiento));
                p.AddWithValue("p_id_segundo_procedimiento", Valor(dto.IdSegundoProcedimiento));
                p.AddWithValue("p_guardar_como_borrador",    Bit(dto.GuardarComoBorrador));
                p.AddWithValue("p_id_usuario",               idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_suministro") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            }, ct);
    }

    public Task<RespuestaDto<object>> CambiarEstadoSuministroAsync(
        long idSuministro, string estado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoSuministro",
            p =>
            {
                p.AddWithValue("p_id_suministro", idSuministro);
                p.AddWithValue("p_estado",        estado);
                p.AddWithValue("p_id_usuario",    idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    private static SuministroListaItemDto LeerListaItem(MySqlDataReader r) => new(
        IdSuministro:       EnteroLargo(r, "id_suministro"),
        Codigo:             Texto(r, "codigo") ?? "",
        Clase:              Texto(r, "clase") ?? "",
        ClaseLabel:         Texto(r, "clase_label") ?? "",
        Tipo:               Texto(r, "tipo") ?? "",
        TipoLabel:          Texto(r, "tipo_label") ?? "",
        Subtipo:            Texto(r, "subtipo") ?? "",
        SubtipoLabel:       Texto(r, "subtipo_label") ?? "",
        Descripcion:        Texto(r, "descripcion") ?? "",
        Marca:              Texto(r, "marca") ?? "",
        Modelo:             Texto(r, "modelo") ?? "",
        CtaContable:        Texto(r, "cta_contable") ?? "",
        Procedencia:        Texto(r, "procedencia") ?? "",
        ProcedenciaLabel:   Texto(r, "procedencia_label") ?? "",
        Estado:             Texto(r, "estado") ?? "",
        EsActivoEnCatalogo: Booleano(r, "es_activo_en_catalogo"),
        UsarEnPropuestas:   Booleano(r, "usar_en_propuestas"));
}
