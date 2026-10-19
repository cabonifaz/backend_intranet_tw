using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Caché, log y consumo de la consulta de RUC.</summary>
public class ConsultaRucRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IConsultaRucRepositorio
{
    public Task<RespuestaDto<LecturaCacheRucDto>> ObtenerAsync(string ruc, int diasVigencia, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerConsultaRuc",
            p =>
            {
                p.AddWithValue("p_ruc",           ruc);
                p.AddWithValue("p_dias_vigencia", diasVigencia);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                RucEnCacheDto? cache = null;
                if (await r.ReadAsync(ct))
                    cache = new RucEnCacheDto(
                        Ruc:          Texto(r, "ruc") ?? ruc,
                        RazonSocial:  Texto(r, "razon_social") ?? "",
                        Estado:       Texto(r, "estado"),
                        Condicion:    Texto(r, "condicion"),
                        Direccion:    Texto(r, "direccion"),
                        Ubigeo:       Texto(r, "ubigeo"),
                        Departamento: Texto(r, "departamento"),
                        Provincia:    Texto(r, "provincia"),
                        Distrito:     Texto(r, "distrito"),
                        Fuente:       Texto(r, "fuente"),
                        FechaDato:    EsNulo(r, "fecha_dato") ? null : DateOnly.FromDateTime(Convert.ToDateTime(r["fecha_dato"])),
                        Proveedor:    Texto(r, "proveedor") ?? "",
                        ConsultadoEn: Convert.ToDateTime(r["consultado_en"]));

                await r.NextResultAsync(ct);
                ClienteExistenteRucDto? cliente = null;
                if (await r.ReadAsync(ct))
                    cliente = new ClienteExistenteRucDto(
                        EnteroLargo(r, "id_cliente"), Texto(r, "razon_social") ?? "", Texto(r, "estado"));

                return new RespuestaDto<LecturaCacheRucDto>(2, mensaje, new LecturaCacheRucDto(cache, cliente));
            }, ct);

    public Task<RespuestaDto<object>> GuardarAsync(
        DatosRucProveedorDto d, string proveedor, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarConsultaRuc",
            p =>
            {
                p.AddWithValue("p_ruc",          d.Ruc);
                p.AddWithValue("p_razon_social", d.RazonSocial);
                p.AddWithValue("p_estado",       Valor(d.Estado));
                p.AddWithValue("p_condicion",    Valor(d.Condicion));
                p.AddWithValue("p_direccion",    Valor(d.Direccion));
                p.AddWithValue("p_ubigeo",       Valor(d.Ubigeo));
                p.AddWithValue("p_fuente",       Valor(d.Fuente));
                p.AddWithValue("p_fecha_dato",   d.FechaDato.HasValue ? d.FechaDato.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value);
                p.AddWithValue("p_proveedor",    proveedor);
                p.AddWithValue("p_id_usuario",   idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    public Task<RespuestaDto<object>> RegistrarLogAsync(
        string ruc, string proveedor, string resultado, int? codigoHttp, string? detalle,
        int duracionMs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarConsultaRucLog",
            p =>
            {
                p.AddWithValue("p_ruc",         ruc);
                p.AddWithValue("p_proveedor",   proveedor);
                p.AddWithValue("p_resultado",   resultado);
                p.AddWithValue("p_codigo_http", Valor(codigoHttp));
                p.AddWithValue("p_detalle",     Valor(detalle));
                p.AddWithValue("p_duracion_ms", duracionMs);
                p.AddWithValue("p_id_usuario",  idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    public Task<RespuestaDto<UsoConsultaRucDto>> ObtenerUsoAsync(int meses, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerUsoConsultaRuc",
            p => p.AddWithValue("p_meses", meses),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var periodos = new List<UsoConsultaRucPeriodoDto>();
                while (await r.ReadAsync(ct))
                    periodos.Add(new UsoConsultaRucPeriodoDto(
                        Periodo:            Texto(r, "periodo") ?? "",
                        Proveedor:          Texto(r, "proveedor") ?? "",
                        Llamadas:           Entero(r, "llamadas"),
                        Encontrados:        Entero(r, "encontrados"),
                        NoEncontrados:      Entero(r, "no_encontrados"),
                        Limitados:          Entero(r, "limitados"),
                        Errores:            Entero(r, "errores"),
                        DuracionPromedioMs: EnteroNulo(r, "duracion_promedio_ms")));

                await r.NextResultAsync(ct);
                int enCache = await r.ReadAsync(ct) ? Entero(r, "rucs_en_cache") : 0;

                return new RespuestaDto<UsoConsultaRucDto>(2, mensaje, new UsoConsultaRucDto(periodos, enCache));
            }, ct);
}
