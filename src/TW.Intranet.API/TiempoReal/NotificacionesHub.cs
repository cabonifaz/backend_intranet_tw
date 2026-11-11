using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Caching.Memory;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.TiempoReal;

/// <summary>
/// HU-90 parte 2 — Hub de notificaciones y eventos en tiempo real (/hubs/notificaciones, solo WebSockets).
/// Autenticación: el mismo JWT de la intranet, que por WebSocket viaja en la query (access_token); solo se lee en esta ruta
/// (JwtBearerEvents.OnMessageReceived) y pasa por la misma validación de sesión que el resto de la API. El token de la app móvil
/// no entra (no es una ruta permitida para su token). La conexión se cierra sola cuando vence el token.
/// Grupos al conectarse: user_{id}, rol_{rol} y permiso_{accion} por cada acción de GruposTiempoReal.AccionesConGrupo que tenga.
/// Grupos de entidad (oc_{id}, os_{id}, propuesta_{id}): el front los pide con SuscribirEntidad; se valida el permiso de ver el módulo.
/// El cliente no envía datos de negocio por aquí: solo se suscribe. Todo lo demás sigue por REST.
/// </summary>
[Authorize]
public sealed class NotificacionesHub(
    ObtenerMisAccionesCasoDeUso obtenerAcciones,
    IMemoryCache                cache,
    IConfiguration              configuracion,
    ILogger<NotificacionesHub>  logger) : Hub
{
    public const string Ruta = "/hubs/notificaciones";

    /// <summary>Máximo de grupos de entidad por conexión (evita que un cliente se suscriba a todo).</summary>
    private const int MaximoSuscripciones = 50;
    private const string ClaveSuscripciones = "suscripciones";

    private long IdUsuario =>
        long.TryParse(Context.User?.FindFirstValue(ClaimTypes.NameIdentifier) ?? Context.User?.FindFirstValue("sub"), out var id) ? id : 0;

    public override async Task OnConnectedAsync()
    {
        var idUsuario = IdUsuario;
        if (idUsuario <= 0)
        {
            Context.Abort();
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, GruposTiempoReal.Usuario(idUsuario));

        var rol = Context.User?.FindFirstValue("rol");
        if (!string.IsNullOrWhiteSpace(rol))
            await Groups.AddToGroupAsync(Context.ConnectionId, GruposTiempoReal.Rol(rol));

        var permitidas = await AccionesPermitidasAsync(idUsuario);
        foreach (var accion in GruposTiempoReal.AccionesConGrupo)
            if (permitidas is null || permitidas.Contains(accion))
                await Groups.AddToGroupAsync(Context.ConnectionId, GruposTiempoReal.Permiso(accion));

        await base.OnConnectedAsync();
    }

    /// <summary>Recibir los eventos de una entidad abierta en pantalla. tipo: oc · os · propuesta. Devuelve false si no se permite.</summary>
    public async Task<bool> SuscribirEntidad(string tipo, long id)
    {
        tipo = (tipo ?? "").Trim().ToLowerInvariant();
        if (id <= 0 || !GruposTiempoReal.EntidadesSuscribibles.TryGetValue(tipo, out var accionesRequeridas))
            return false;

        var suscripciones = Suscripciones();
        var grupo = GruposTiempoReal.Entidad(tipo, id);
        if (suscripciones.Contains(grupo)) return true;
        if (suscripciones.Count >= MaximoSuscripciones) return false;

        var idUsuario = IdUsuario;
        var permitidas = await AccionesPermitidasAsync(idUsuario);
        if (permitidas is not null && !accionesRequeridas.Any(permitidas.Contains))
        {
            logger.LogWarning("Tiempo real: el usuario {IdUsuario} no tiene permiso para suscribirse a {Grupo}.", idUsuario, grupo);
            return false;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, grupo, Context.ConnectionAborted);
        suscripciones.Add(grupo);
        return true;
    }

    /// <summary>Dejar de recibir los eventos de una entidad (al cerrar el modal o la ficha).</summary>
    public async Task<bool> DesuscribirEntidad(string tipo, long id)
    {
        tipo = (tipo ?? "").Trim().ToLowerInvariant();
        if (id <= 0 || !GruposTiempoReal.EntidadesSuscribibles.ContainsKey(tipo))
            return false;

        var grupo = GruposTiempoReal.Entidad(tipo, id);
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, grupo, Context.ConnectionAborted);
        Suscripciones().Remove(grupo);
        return true;
    }

    private HashSet<string> Suscripciones()
    {
        if (Context.Items.TryGetValue(ClaveSuscripciones, out var valor) && valor is HashSet<string> existentes)
            return existentes;
        var nuevas = new HashSet<string>(StringComparer.Ordinal);
        Context.Items[ClaveSuscripciones] = nuevas;
        return nuevas;
    }

    /// <summary>Acciones permitidas (misma caché de 30 s que [RequierePermiso]). null = validación de permisos apagada (todo permitido).</summary>
    private async Task<HashSet<string>?> AccionesPermitidasAsync(long idUsuario)
    {
        if (!configuracion.GetValue("Permisos:ValidarEnBack", true))
            return null;

        var acciones = await PermisosFilter.ObtenerAccionesAsync(obtenerAcciones, cache, idUsuario, Context.ConnectionAborted);
        return acciones.Where(a => a.Permitido).Select(a => a.Accion).ToHashSet(StringComparer.Ordinal);
    }
}
