using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Llegada forzada de la app móvil (App Mobile HU-06 / HU-31). Todo pasa por SP.</summary>
public class LlegadaForzadaRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), ILlegadaForzadaRepositorio
{
    public Task<RespuestaDto<bool>> SolicitarAsync(
        long idUsuario, long idOs, decimal latitud, decimal longitud, decimal precisionMetros, int intentos, string? motivo, CancellationToken ct) =>
        EjecutarAsync("SP_SolicitarLlegadaForzadaMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_latitud",    latitud);
                p.AddWithValue("p_longitud",   longitud);
                p.AddWithValue("p_precision",  precisionMetros);
                p.AddWithValue("p_intentos",   intentos);
                p.AddWithValue("p_motivo",     Valor(motivo));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<List<SolicitudLlegadaForzadaDto>>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<List<SolicitudLlegadaForzadaDto>>("SP_ObtenerLlegadasForzadas",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                var lista = new List<SolicitudLlegadaForzadaDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new SolicitudLlegadaForzadaDto(
                        EnteroLargo(r, "id_solicitud"),
                        EnteroLargo(r, "id_os"),
                        Texto(r, "numero_os") ?? string.Empty,
                        Texto(r, "cliente"),
                        Texto(r, "sede"),
                        Fecha(r, "fecha_ejecucion"),
                        Texto(r, "hora_inicio"),
                        Texto(r, "tecnico"),
                        Texto(r, "estado") ?? string.Empty,
                        Texto(r, "motivo"),
                        Entero(r, "intentos"),
                        DecimalNulo(r, "latitud"),
                        DecimalNulo(r, "longitud"),
                        DecimalNulo(r, "precision_metros"),
                        EnteroNulo(r, "distancia_m"),
                        DecimalNulo(r, "lat_planta"),
                        DecimalNulo(r, "lon_planta"),
                        Entero(r, "radio_m"),
                        Texto(r, "area_destino"),
                        Texto(r, "area"),
                        FechaHora(r, "solicitado_en"),
                        Texto(r, "jefe"),
                        FechaHora(r, "resuelto_en"),
                        Texto(r, "comentario"),
                        FechaHora(r, "usada_en")));
                return new RespuestaDto<List<SolicitudLlegadaForzadaDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<bool>> ResolverAsync(long idJefe, long idOs, bool aprobar, string? comentario, CancellationToken ct) =>
        EjecutarAsync("SP_ResolverLlegadaForzada",
            p =>
            {
                p.AddWithValue("p_id_jefe",    idJefe);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_aprobar",    Bit(aprobar));
                p.AddWithValue("p_comentario", Valor(comentario));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);
}
