using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Reloj marcador de jornada de la app móvil (App Mobile HU-20).</summary>
public class JornadaMovilRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IJornadaMovilRepositorio
{
    public Task<RespuestaDto<JornadaMovilDto>> ObtenerAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<JornadaMovilDto>("SP_ObtenerJornadaMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<JornadaMovilDto>(1, "No se pudo leer la jornada.");
                string fecha = Texto(r, "fecha") ?? "", ahora = Texto(r, "ahora_utc") ?? "", estado = Texto(r, "estado") ?? "sin_iniciar";
                string? siguiente = Texto(r, "siguiente");
                string ini = Texto(r, "inicio_programado") ?? "", fin = Texto(r, "fin_programado") ?? "";
                int tolerancia = Entero(r, "tolerancia_min"), refrigerio = Entero(r, "refrigerio_max_min");

                await r.NextResultAsync(ct);
                var marcaciones = new List<MarcacionJornadaDto>();
                while (await r.ReadAsync(ct))
                    marcaciones.Add(new MarcacionJornadaDto(Texto(r, "tipo") ?? "", Texto(r, "hora") ?? "", Texto(r, "marcado_utc") ?? "", Texto(r, "lugar"),
                        DecimalNulo(r, "latitud"), DecimalNulo(r, "longitud"), EnteroNulo(r, "precision_m"), Texto(r, "puntualidad"),
                        EnteroNulo(r, "minutos_diferencia"), Booleano(r, "sin_conexion")));

                await r.NextResultAsync(ct);
                ResumenJornadaDto? resumen = null;
                if (await r.ReadAsync(ct))
                    resumen = new ResumenJornadaDto(Entero(r, "trabajado_min"), Entero(r, "refrigerio_min"), Texto(r, "ingreso"), EnteroNulo(r, "minutos_tardanza"));

                return new RespuestaDto<JornadaMovilDto>(2, mensaje,
                    new JornadaMovilDto(fecha, ahora, estado, siguiente, ini, fin, tolerancia, refrigerio, marcaciones, resumen));
            }, ct);

    public Task<RespuestaDto<MarcacionRegistradaDto>> MarcarAsync(
        long idUsuario, string tipo, decimal latitud, decimal longitud, decimal? precisionMetros, DateTime? marcadoUtc, bool sinConexion, CancellationToken ct) =>
        EjecutarAsync<MarcacionRegistradaDto>("SP_RegistrarMarcacionJornadaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_tipo",         tipo);
                p.AddWithValue("p_latitud",      latitud);
                p.AddWithValue("p_longitud",     longitud);
                p.AddWithValue("p_precision",    Valor(precisionMetros));
                p.AddWithValue("p_marcado_utc",  Valor(marcadoUtc));
                p.AddWithValue("p_sin_conexion", Bit(sinConexion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<MarcacionRegistradaDto>(1, "No se pudo registrar la marcación.");
                return new RespuestaDto<MarcacionRegistradaDto>(2, mensaje, new MarcacionRegistradaDto(
                    Texto(r, "tipo") ?? tipo, Booleano(r, "repetida"), Texto(r, "estado") ?? "", Texto(r, "siguiente"), Texto(r, "hora"), Texto(r, "lugar"),
                    Texto(r, "puntualidad"), EnteroNulo(r, "minutos_diferencia")));
            }, ct);

    public Task<RespuestaDto<UbicacionRegistradaDto>> RegistrarUbicacionAsync(
        long idUsuario, decimal latitud, decimal longitud, decimal? precisionMetros, decimal? velocidadKmh, decimal? altitudM, CancellationToken ct) =>
        EjecutarAsync<UbicacionRegistradaDto>("SP_RegistrarUbicacionJornadaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_latitud",    latitud);
                p.AddWithValue("p_longitud",   longitud);
                p.AddWithValue("p_precision",  Valor(precisionMetros));
                p.AddWithValue("p_velocidad",  Valor(velocidadKmh));
                p.AddWithValue("p_altitud",    Valor(altitudM));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<UbicacionRegistradaDto>(2, mensaje, new UbicacionRegistradaDto(await r.ReadAsync(ct) && Booleano(r, "Guardada")));
            }, ct);
}
