using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Registro de demoras en ruta de la app móvil (App Mobile HU-05).</summary>
public class DemorasMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IDemorasMovilRepositorio
{
    public Task<RespuestaDto<ContextoDemorasMovilDto>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<ContextoDemorasMovilDto>("SP_ObtenerDemorasMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                // 2. Contexto
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ContextoDemorasMovilDto>(1, "Servicio no encontrado o no asignado a tu usuario.");

                var idOs2        = EnteroLargo(r, "id_os");
                var numero       = Texto(r, "numero_os") ?? string.Empty;
                var estado       = Texto(r, "estado_os") ?? string.Empty;
                var cliente      = Texto(r, "cliente");
                var sede         = Texto(r, "sede");
                var salida       = FechaHora(r, "salida_en");
                var enRuta       = EnteroNulo(r, "en_ruta_minutos");
                var llegada      = FechaHora(r, "llegada_en");
                var enPlanta     = EnteroNulo(r, "en_planta_minutos");
                var etaOriginal  = FechaHora(r, "eta_original");
                var minutos      = Entero(r, "minutos_demora");
                var etaVigente   = FechaHora(r, "eta_vigente");
                var inicioPrev   = FechaHora(r, "inicio_previsto");
                var ahora        = FechaHora(r, "ahora") ?? DateTime.UtcNow.AddHours(-5);
                var puedeLlegada = Booleano(r, "puede_llegada");
                var puedeIngreso = Booleano(r, "puede_ingreso");
                var motivoNo     = Texto(r, "motivo_no_registra");

                // 3. Motivos
                var motivos = new List<MotivoDemoraMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    motivos.Add(new MotivoDemoraMovilDto(Entero(r, "id_motivo"), Texto(r, "nombre") ?? string.Empty,
                        Texto(r, "codigo"), Texto(r, "ambito") ?? "ambos"));

                // 4. Demoras ya registradas
                var demoras = new List<DemoraRegistradaMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    demoras.Add(new DemoraRegistradaMovilDto(
                        EnteroLargo(r, "id_demora"),
                        Texto(r, "tipo") ?? "llegada",
                        Texto(r, "motivo"),
                        Entero(r, "duracion_minutos"),
                        Texto(r, "descripcion"),
                        FechaHora(r, "fecha_registro"),
                        FechaHora(r, "eta_anterior"),
                        FechaHora(r, "eta_recalculada"),
                        Booleano(r, "tiene_foto"),
                        DecimalNulo(r, "latitud"),
                        DecimalNulo(r, "longitud")));

                return new RespuestaDto<ContextoDemorasMovilDto>(2, mensaje, new ContextoDemorasMovilDto(
                    idOs2, numero, estado, cliente, sede, salida, enRuta, llegada, enPlanta, etaOriginal, minutos, etaVigente,
                    inicioPrev, ahora, puedeLlegada, puedeIngreso, motivoNo, motivos, demoras));
            }, ct);

    public Task<RespuestaDto<ResultadoDemoraMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, string tipo, NuevaDemoraMovilDto d, string? rutaFoto, CancellationToken ct) =>
        EjecutarAsync<ResultadoDemoraMovilDto>("SP_RegistrarDemoraMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_os",       idOs);
                p.AddWithValue("p_tipo",        tipo);
                p.AddWithValue("p_id_motivo",   d.IdMotivo);
                p.AddWithValue("p_duracion",    d.DuracionMinutos);
                p.AddWithValue("p_descripcion", Valor(d.Descripcion));
                p.AddWithValue("p_latitud",     Valor(d.Latitud));
                p.AddWithValue("p_longitud",    Valor(d.Longitud));
                p.AddWithValue("p_precision",   Valor(d.PrecisionMetros));
                p.AddWithValue("p_foto",        Valor(rutaFoto));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoDemoraMovilDto>(1, "No se pudo registrar la demora.");

                return new RespuestaDto<ResultadoDemoraMovilDto>(2, mensaje, new ResultadoDemoraMovilDto(
                    EnteroLargo(r, "id_demora"),
                    Texto(r, "tipo") ?? tipo,
                    FechaHora(r, "eta_original"),
                    FechaHora(r, "eta_anterior"),
                    FechaHora(r, "eta_recalculada"),
                    Entero(r, "notificados")));
            }, ct);
}
