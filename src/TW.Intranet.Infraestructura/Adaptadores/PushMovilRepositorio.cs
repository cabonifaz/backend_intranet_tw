using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Teléfonos registrados para recibir notificaciones push (App Mobile).</summary>
public class PushMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IPushMovilRepositorio
{
    public Task<RespuestaDto<bool>> RegistrarAsync(long idUsuario, RegistrarDispositivoPushEntradaDto entrada, CancellationToken ct) =>
        EjecutarAsync("SP_RegistrarDispositivoPushMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_dispositivo", entrada.IdDispositivo);
                p.AddWithValue("p_token",          entrada.Token);
                p.AddWithValue("p_plataforma",     entrada.Plataforma);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<bool>> QuitarAsync(long idUsuario, string idDispositivo, CancellationToken ct) =>
        EjecutarAsync("SP_QuitarDispositivoPushMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_dispositivo", idDispositivo);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    public Task<RespuestaDto<List<DispositivoPushDto>>> ObtenerDispositivosAsync(IReadOnlyCollection<long> idsUsuario, CancellationToken ct) =>
        EjecutarAsync<List<DispositivoPushDto>>("SP_ObtenerDispositivosPushMovil",
            p => p.AddWithValue("p_ids_usuario", string.Join(',', idsUsuario)),
            async (r, mensaje) =>
            {
                var lista = new List<DispositivoPushDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new DispositivoPushDto(EnteroLargo(r, "id_usuario"), Texto(r, "token") ?? string.Empty));
                return new RespuestaDto<List<DispositivoPushDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<int>> DarDeBajaAsync(IReadOnlyCollection<string> tokens, CancellationToken ct) =>
        EjecutarAsync<int>("SP_DarDeBajaTokensPushMovil",
            p => p.AddWithValue("p_tokens", string.Join(',', tokens)),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var bajas = await r.ReadAsync(ct) ? Entero(r, "bajas") : 0;
                return new RespuestaDto<int>(2, mensaje, bajas);
            }, ct);
}
