using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>App móvil sin señal — SP_RegistrarEnvioDiferidoMovil y SP_ListarEnviosDiferidosMovil.</summary>
public class EnvioDiferidoMovilRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IEnvioDiferidoMovilRepositorio
{
    public Task<RespuestaDto<object>> RegistrarAsync(
        long idUsuario, string metodo, string ruta, long? idOs, long? idOsEquipo, DateTime capturadoUtc, string? motivo, int intentos, CancellationToken ct) =>
        EjecutarAsync<object>("SP_RegistrarEnvioDiferidoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_metodo",        metodo);
                p.AddWithValue("p_ruta",          ruta);
                p.AddWithValue("p_id_os",         Valor(idOs));
                p.AddWithValue("p_id_os_equipo",  Valor(idOsEquipo));
                p.AddWithValue("p_capturado_utc", capturadoUtc);
                p.AddWithValue("p_motivo",        Valor(motivo));
                p.AddWithValue("p_intentos",      intentos);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    public Task<RespuestaDto<IReadOnlyList<EnvioDiferidoDto>>> ListarAsync(long idOs, long? idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<IReadOnlyList<EnvioDiferidoDto>>("SP_ListarEnviosDiferidosMovil",
            p =>
            {
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", Valor(idOsEquipo));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<EnvioDiferidoDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new EnvioDiferidoDto(
                        EnteroLargo(r, "id_envio"), EnteroLargo(r, "id_usuario"), Texto(r, "tecnico"), EnteroLargoNulo(r, "id_os"), EnteroLargoNulo(r, "id_os_equipo"),
                        Texto(r, "tipo") ?? "otro", Texto(r, "metodo") ?? string.Empty, FechaHora(r, "capturado_en"), FechaHora(r, "recibido_en"),
                        Entero(r, "retraso_seg"), Texto(r, "motivo") ?? "otro", Entero(r, "intentos")));
                return new RespuestaDto<IReadOnlyList<EnvioDiferidoDto>>(2, mensaje, lista);
            }, ct);
}
