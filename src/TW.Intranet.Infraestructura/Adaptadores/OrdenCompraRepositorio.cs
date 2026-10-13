using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;
using MySqlConnector;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-22 — Órdenes de compra recibidas del cliente.</summary>
public class OrdenCompraRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IOrdenCompraRepositorio
{
    private static decimal Dec(MySqlDataReader r, string c) => DecimalNulo(r, c) ?? 0m;
    private static int Ent(MySqlDataReader r, string c) => (int)(DecimalNulo(r, c) ?? 0m);

    public Task<RespuestaDto<PreparacionOrdenCompraDto>> PrepararAsync(long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_propuesta", idPropuesta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<PreparacionOrdenCompraDto>(3, "No se pudo leer la propuesta.");
                var propuesta = new PropuestaOrdenCompraDto
                {
                    IdPropuesta         = EnteroLargo(r, "id_propuesta"),
                    Numero              = Texto(r, "numero") ?? "",
                    Version             = Ent(r, "version"),
                    IdCliente           = EnteroLargo(r, "id_cliente"),
                    RazonSocial         = Texto(r, "razon_social") ?? "",
                    Ruc                 = Texto(r, "ruc"),
                    IdRequerimiento     = EnteroLargoNulo(r, "id_requerimiento"),
                    NumeroRq            = Texto(r, "numero_rq"),
                    Total               = Dec(r, "total"),
                    IdMoneda            = Ent(r, "id_moneda"),
                    Moneda              = Texto(r, "moneda"),
                    MonedaSimbolo       = Texto(r, "moneda_simbolo"),
                    MonedaNombre        = Texto(r, "moneda_nombre"),
                    FechaAceptacion     = FechaHora(r, "fecha_aceptacion"),
                    TipoAceptacion      = Texto(r, "tipo_aceptacion"),
                    IdResponsable       = EnteroLargo(r, "id_responsable"),
                    Responsable         = Texto(r, "responsable"),
                    FechaServidor       = FechaHora(r, "fecha_servidor"),
                    VigenciaDiasDefecto = Ent(r, "vigencia_dias_defecto"),
                };

                await r.NextResultAsync(ct);
                var monedas = new List<MonedaOrdenCompraDto>();
                while (await r.ReadAsync(ct))
                    monedas.Add(new MonedaOrdenCompraDto(Ent(r, "id"), Texto(r, "nombre") ?? "", Texto(r, "simbolo"), Texto(r, "codigo")));

                return new RespuestaDto<PreparacionOrdenCompraDto>(2, mensaje, new PreparacionOrdenCompraDto(propuesta, monedas));
            },
            ct);

    private static void Parametros(MySqlParameterCollection p, long idPropuesta, DatosOrdenCompraDto d, long idUsuario,
                                   string? ruta, string? nombre, long? tamano, string? hash, bool soloValidar)
    {
        p.AddWithValue("p_id_usuario",      idUsuario);
        p.AddWithValue("p_id_propuesta",    idPropuesta);
        p.AddWithValue("p_numero_oc",       Valor(d.NumeroOc));
        p.AddWithValue("p_fecha_oc",        Valor(d.FechaOc));
        p.AddWithValue("p_fecha_recepcion", Valor(d.FechaRecepcion));
        p.AddWithValue("p_id_moneda",       Valor(d.IdMoneda));
        p.AddWithValue("p_monto",           Valor(d.Monto));
        p.AddWithValue("p_vigencia_dias",   Valor(d.VigenciaDias));
        p.AddWithValue("p_observaciones",   Valor(d.Observaciones));
        p.AddWithValue("p_ruta_pdf",        Valor(ruta));
        p.AddWithValue("p_nombre_pdf",      Valor(nombre));
        p.AddWithValue("p_tamano_pdf",      Valor(tamano));
        p.AddWithValue("p_hash_pdf",        Valor(hash));
        p.AddWithValue("p_solo_validar",    Bit(soloValidar));
    }

    public Task<RespuestaDto<CoberturaOrdenCompraDto>> ValidarAsync(long idPropuesta, DatosOrdenCompraDto datos, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarOrdenCompra",
            p => Parametros(p, idPropuesta, datos, idUsuario, null, null, null, null, soloValidar: true),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CoberturaOrdenCompraDto>(3, "No se pudo calcular la cobertura.");
                return new RespuestaDto<CoberturaOrdenCompraDto>(2, mensaje, new CoberturaOrdenCompraDto(
                    Texto(r, "estado_cobertura") ?? "", Dec(r, "cobertura_pct"), DecimalNulo(r, "diferencia"),
                    Dec(r, "monto_propuesta"), Ent(r, "id_moneda_propuesta"), Texto(r, "moneda_simbolo_propuesta"),
                    Dec(r, "monto_oc"), Ent(r, "id_moneda_oc"), Texto(r, "moneda_simbolo_oc")));
            },
            ct);

    public Task<RespuestaDto<OrdenCompraRegistradaDto>> RegistrarAsync(long idPropuesta, ComandoOrdenCompra c, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarOrdenCompra",
            p => Parametros(p, idPropuesta, c.Datos, idUsuario, c.RutaPdf, c.NombrePdf, c.TamanoPdf, c.HashPdf, soloValidar: false),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<OrdenCompraRegistradaDto>(3, "No se pudo leer la orden de compra registrada.");
                return new RespuestaDto<OrdenCompraRegistradaDto>(2, mensaje, new OrdenCompraRegistradaDto(
                    EnteroLargo(r, "id_oc"), Texto(r, "numero_oc") ?? "", Texto(r, "estado") ?? "",
                    Texto(r, "estado_cobertura") ?? "", Dec(r, "cobertura_pct"), DecimalNulo(r, "diferencia"),
                    FechaHora(r, "vigencia_hasta"), Texto(r, "siguiente_etapa") ?? "", Ent(r, "notificados")));
            },
            ct);

    public Task<RespuestaDto<RutaPdfOrdenCompraDto>> ObtenerRutaPdfAsync(long idOc, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPdfOrdenCompra",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_oc",      idOc);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RutaPdfOrdenCompraDto>(1, "La orden de compra no tiene PDF adjunto.");
                return new RespuestaDto<RutaPdfOrdenCompraDto>(2, mensaje,
                    new RutaPdfOrdenCompraDto(Texto(r, "ruta") ?? "", Texto(r, "nombre_archivo") ?? "orden-compra.pdf"));
            },
            ct);
}
