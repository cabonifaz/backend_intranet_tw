using Microsoft.AspNetCore.SignalR;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.API.TiempoReal;

/// <summary>
/// Adaptador del puerto INotificadorTiempoReal con SignalR. Cada evento sale con el sobre { evento, fecha, datos }.
/// Nunca lanza: si no puede emitir, lo deja en el log y el caso de uso sigue igual.
/// Una sola instancia en Railway: los grupos viven en memoria. Si algún día hay varias réplicas, hace falta un backplane
/// (paquete Microsoft.AspNetCore.SignalR.StackExchangeRedis + variable Redis__Conexion) para que un evento llegue a los clientes
/// conectados a otra réplica.
/// </summary>
public sealed class NotificadorSignalR(IHubContext<NotificacionesHub> hub, ILogger<NotificadorSignalR> logger) : INotificadorTiempoReal
{
    public Task EnviarAUsuariosAsync(IEnumerable<long> idsUsuario, string evento, object datos, CancellationToken ct = default)
        => EnviarAGruposAsync(idsUsuario.Where(id => id > 0).Distinct().Select(GruposTiempoReal.Usuario), evento, datos, ct);

    public async Task EnviarAGruposAsync(IEnumerable<string> grupos, string evento, object datos, CancellationToken ct = default)
    {
        try
        {
            var lista = grupos.Where(g => !string.IsNullOrWhiteSpace(g)).Distinct(StringComparer.Ordinal).ToList();
            if (lista.Count == 0) return;

            await hub.Clients.Groups(lista).SendAsync(evento, new EventoTiempoRealDto(evento, DateTime.Now, datos), ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Tiempo real: no se pudo emitir {Evento}.", evento);
        }
    }
}
