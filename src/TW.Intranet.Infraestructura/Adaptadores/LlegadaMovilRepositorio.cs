using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Registro de llegada con validación GPS de la app móvil (App Mobile HU-06).</summary>
public class LlegadaMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ILlegadaMovilRepositorio
{
    public Task<RespuestaDto<LlegadaMovilDto>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<LlegadaMovilDto>("SP_ObtenerLlegadaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<LlegadaMovilDto>(1, "Servicio no encontrado o no asignado a tu usuario.");

                var latRef = DecimalNulo(r, "lat_ref");
                var lonRef = DecimalNulo(r, "lon_ref");
                var radio  = Entero(r, "radio_m");
                var llegadaEn = FechaHora(r, "llegada_en");

                return new RespuestaDto<LlegadaMovilDto>(2, mensaje, new LlegadaMovilDto(
                    EnteroLargo(r, "id_os"),
                    Texto(r, "numero_os") ?? string.Empty,
                    Texto(r, "estado_os") ?? string.Empty,
                    Texto(r, "cliente"),
                    Texto(r, "sede"),
                    Texto(r, "direccion"),
                    Texto(r, "hora_programada"),
                    latRef is { } la && lonRef is { } lo ? new ReferenciaGpsMovilDto(la, lo, radio) : null,
                    FechaHora(r, "salida_en"),
                    llegadaEn is null ? null : new LlegadaRegistradaMovilDto(
                        llegadaEn, DecimalNulo(r, "llegada_lat"), DecimalNulo(r, "llegada_lon"), DecimalNulo(r, "llegada_precision"),
                        EnteroNulo(r, "llegada_distancia"), Texto(r, "llegada_resultado")),
                    Booleano(r, "puede_registrar"),
                    Entero(r, "precision_max_m"),
                    Texto(r, "motivo_no_registra"),
                    DecimalNulo(r, "origen_lat") is { } olat && DecimalNulo(r, "origen_lon") is { } olon ? new PuntoGpsLlegadaDto(olat, olon) : null));
            }, ct);

    public Task<RespuestaDto<ValidacionLlegadaMovilDto>> ValidarAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal precisionMetros, CancellationToken ct) =>
        EjecutarAsync<ValidacionLlegadaMovilDto>("SP_ValidarLlegadaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_latitud",    latitud);
                p.AddWithValue("p_longitud",   longitud);
                p.AddWithValue("p_precision",  precisionMetros);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ValidacionLlegadaMovilDto>(1, "No se pudo validar la ubicación.");

                return new RespuestaDto<ValidacionLlegadaMovilDto>(2, mensaje, new ValidacionLlegadaMovilDto(
                    Texto(r, "resultado") ?? "fuera_rango",
                    Booleano(r, "registrable"),
                    EnteroNulo(r, "distancia_m"),
                    EnteroNulo(r, "radio_m"),
                    DecimalNulo(r, "precision_m") ?? precisionMetros,
                    Texto(r, "mensaje") ?? string.Empty));
            }, ct);

    public Task<RespuestaDto<ResultadoLlegadaMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal precisionMetros, DateTime? capturadoUtc, CancellationToken ct) =>
        EjecutarAsync<ResultadoLlegadaMovilDto>("SP_RegistrarLlegadaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_id_os",         idOs);
                p.AddWithValue("p_latitud",       latitud);
                p.AddWithValue("p_longitud",      longitud);
                p.AddWithValue("p_precision",     precisionMetros);
                p.AddWithValue("p_capturado_utc", Valor(capturadoUtc));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoLlegadaMovilDto>(1, "No se pudo registrar la llegada.");

                return new RespuestaDto<ResultadoLlegadaMovilDto>(2, mensaje, new ResultadoLlegadaMovilDto(
                    EnteroLargo(r, "id_evento"),
                    FechaHora(r, "llegada_en"),
                    EnteroNulo(r, "distancia_m"),
                    DecimalNulo(r, "precision_m"),
                    Texto(r, "resultado") ?? "valida",
                    Booleano(r, "ya_registrada"),
                    Booleano(r, "diferida")));
            }, ct);
}
