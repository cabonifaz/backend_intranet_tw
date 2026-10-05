using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Procedimientos metrológicos (HU-87).</summary>
public class ProcedimientosRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IProcedimientosRepositorio
{
    public Task<RespuestaDto<ProcedimientosPaginadoDto>> ObtenerProcedimientosAsync(
        string? busqueda, int? anio, string? estado, int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerProcedimientos",
            p =>
            {
                p.AddWithValue("p_busqueda",   Valor(busqueda));
                p.AddWithValue("p_anio",       Valor(anio));
                p.AddWithValue("p_estado",     Valor(estado));
                p.AddWithValue("p_pagina",     pagina);
                p.AddWithValue("p_por_pagina", porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<ProcedimientoListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerListaItem(r));

                int total = await LeerTotalAsync(r, ct);
                return new RespuestaDto<ProcedimientosPaginadoDto>(2, mensaje,
                    new ProcedimientosPaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<ProcedimientoDetalleDto>> ObtenerProcedimientoPorIdAsync(long idProcedimiento, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerProcedimientoPorId",
            p => p.AddWithValue("p_id_procedimiento", idProcedimiento),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ProcedimientoDetalleDto>(1, "Procedimiento no encontrado.");

                var l = LeerListaItem(r);
                var detalle = new ProcedimientoDetalleDto(
                    l.IdProcedimiento, l.Codigo, l.Anio, l.Version, l.EsFormatoDigitalIso,
                    l.NormaBase, l.AutorNorma, l.Descripcion, l.Estado, l.FechaRegistro,
                    EsActivo:          Booleano(r, "es_activo"),
                    UrlPdfAprobado:    Texto(r, "url_pdf_aprobado") ?? "",
                    UsuarioRegistro:   Texto(r, "usuario_registro") ?? "",
                    PcRegistro:        Texto(r, "pc_registro") ?? "",
                    FechaModificacion: FechaHora(r, "fecha_modificacion"),
                    TotalEdiciones:    Entero(r, "total_ediciones"));

                return new RespuestaDto<ProcedimientoDetalleDto>(2, mensaje, detalle);
            }, ct);

    public Task<RespuestaDto<List<OpcionCatalogoDto>>> ObtenerOpcionesAsync(CancellationToken ct)
        => EjecutarAsync("SP_ObtenerProcedimientosOpciones",
            _ => { },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<OpcionCatalogoDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new OpcionCatalogoDto(Texto(r, "value") ?? "", Texto(r, "label") ?? ""));
                return new RespuestaDto<List<OpcionCatalogoDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<long>> GuardarProcedimientoAsync(
        GuardarProcedimientoDto dto, long idUsuario, string? pcRegistro, CancellationToken ct)
        => EjecutarAsync("SP_GuardarProcedimiento",
            p =>
            {
                p.AddWithValue("p_id_procedimiento",       dto.IdProcedimiento);
                p.AddWithValue("p_codigo",                 dto.Codigo!);
                p.AddWithValue("p_anio",                   dto.Anio);
                p.AddWithValue("p_version",                dto.Version);
                p.AddWithValue("p_autor_norma",            Valor(dto.AutorNorma));
                p.AddWithValue("p_norma_base",             Valor(dto.NormaBase));
                p.AddWithValue("p_descripcion",            dto.Descripcion!.Trim());
                p.AddWithValue("p_es_formato_digital_iso", Bit(dto.EsFormatoDigitalIso));
                p.AddWithValue("p_url_pdf_aprobado",       Valor(dto.UrlPdfAprobado));
                p.AddWithValue("p_es_activo",              Bit(dto.EsActivo));
                p.AddWithValue("p_guardar_como_borrador",  Bit(dto.GuardarComoBorrador));
                p.AddWithValue("p_id_usuario",             idUsuario);
                p.AddWithValue("p_pc_registro",            Valor(pcRegistro));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_procedimiento") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            }, ct);

    public Task<RespuestaDto<object>> CambiarEstadoProcedimientoAsync(
        long idProcedimiento, string estado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoProcedimiento",
            p =>
            {
                p.AddWithValue("p_id_procedimiento", idProcedimiento);
                p.AddWithValue("p_estado",           estado);
                p.AddWithValue("p_id_usuario",       idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    private static ProcedimientoListaItemDto LeerListaItem(MySqlDataReader r) => new(
        IdProcedimiento:     EnteroLargo(r, "id_procedimiento"),
        Codigo:              Texto(r, "codigo") ?? "",
        Anio:                Entero(r, "anio"),
        Version:             Entero(r, "version"),
        EsFormatoDigitalIso: Booleano(r, "es_formato_digital_iso"),
        NormaBase:           Texto(r, "norma_base") ?? "",
        AutorNorma:          Texto(r, "autor_norma") ?? "",
        Descripcion:         Texto(r, "descripcion") ?? "",
        Estado:              Texto(r, "estado") ?? "",
        FechaRegistro:       FechaHora(r, "fecha_registro"));
}
