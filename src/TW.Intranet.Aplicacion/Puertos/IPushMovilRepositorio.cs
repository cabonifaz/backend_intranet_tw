using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Teléfonos registrados para recibir notificaciones push (App Mobile).</summary>
public interface IPushMovilRepositorio
{
    Task<RespuestaDto<bool>> RegistrarAsync(long idUsuario, RegistrarDispositivoPushEntradaDto entrada, CancellationToken ct);

    Task<RespuestaDto<bool>> QuitarAsync(long idUsuario, string idDispositivo, CancellationToken ct);

    /// <summary>Los teléfonos con sesión de esos usuarios (máximo 500 por llamada).</summary>
    Task<RespuestaDto<List<DispositivoPushDto>>> ObtenerDispositivosAsync(IReadOnlyCollection<long> idsUsuario, CancellationToken ct);

    /// <summary>Da de baja tokens que el servicio de push dijo que ya no existen (máximo 100 por llamada).</summary>
    Task<RespuestaDto<int>> DarDeBajaAsync(IReadOnlyCollection<string> tokens, CancellationToken ct);
}

/// <summary>Envía las notificaciones al servicio de push (Expo → Firebase). Nunca lanza: los problemas vuelven en el resultado.</summary>
public interface IEnviadorPushMovil
{
    Task<ResultadoEnvioPushDto> EnviarAsync(IReadOnlyList<MensajePushDto> mensajes, CancellationToken ct);
}
