namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// HU-90 parte 2 — Eventos en tiempo real hacia el front (lo implementa el adaptador SignalR de la API).
/// Los nombres de evento están en <see cref="Dtos.EventosTiempoReal"/> y los de grupo en <see cref="Dtos.GruposTiempoReal"/>.
/// Nunca lanza excepciones ni cambia el resultado del caso de uso: si no se puede emitir, solo queda en el log.
/// Los eventos de dominio son SEÑALES DE REFRESCO (ids y estado): el front vuelve a pedir el detalle por REST, donde se validan los permisos.
/// </summary>
public interface INotificadorTiempoReal
{
    /// <summary>Envía el evento a los grupos user_{id} de esos usuarios.</summary>
    Task EnviarAUsuariosAsync(IEnumerable<long> idsUsuario, string evento, object datos, CancellationToken ct = default);

    /// <summary>Envía el evento a grupos (rol_*, permiso_*, oc_*, os_*, propuesta_*…). Un usuario en varios grupos puede recibirlo más de una vez.</summary>
    Task EnviarAGruposAsync(IEnumerable<string> grupos, string evento, object datos, CancellationToken ct = default);
}
