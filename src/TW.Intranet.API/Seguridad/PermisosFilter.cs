using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Caching.Memory;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Seguridad;

/// <summary>
/// Validación de permisos en el back (ticket #4301). Filtro de AUTORIZACIÓN: corre antes del
/// model binding, así un usuario sin permiso recibe 403 aunque envíe datos incompletos.
/// Lee las acciones permitidas del usuario (SP_ObtenerAccionesUsuario, en caché 30 s).
/// Se apaga con la configuración Permisos:ValidarEnBack = false (variable Permisos__ValidarEnBack).
/// </summary>
public class PermisosFilter(
    ObtenerMisAccionesCasoDeUso obtenerAcciones,
    IMemoryCache                cache,
    IConfiguration              configuracion,
    ILogger<PermisosFilter>     log) : IAsyncAuthorizationFilter
{
    private static readonly TimeSpan DuracionCache = TimeSpan.FromSeconds(30);

    public async Task OnAuthorizationAsync(AuthorizationFilterContext contexto)
    {
        var requisito = ObtenerRequisito(contexto);
        if (requisito is null || !configuracion.GetValue("Permisos:ValidarEnBack", true))
            return;

        // Sin sesión: lo resuelve [Authorize] (401), no este filtro.
        var usuario = contexto.HttpContext.User;
        if (usuario.Identity?.IsAuthenticated != true)
            return;

        if (!long.TryParse(usuario.FindFirstValue(ClaimTypes.NameIdentifier) ?? usuario.FindFirstValue("sub"), out var idUsuario))
        {
            contexto.Result = Denegar("Sesión no válida.");
            return;
        }

        var acciones = requisito.Acciones
            .Select(a => a == "@catalogo" ? AccionDeCatalogo(contexto.RouteData.Values["descripcion"]?.ToString()) : a)
            .ToArray();

        var permitidas = await cache.GetOrCreateAsync($"acciones:{idUsuario}", async entrada =>
        {
            entrada.AbsoluteExpirationRelativeToNow = DuracionCache;
            var r = await obtenerAcciones.EjecutarAsync(idUsuario, contexto.HttpContext.RequestAborted);
            return r.IdTipoMensaje == 2 && r.Datos is not null ? r.Datos : new List<AccionPermitidaDto>();
        }) ?? [];

        if (permitidas.Any(p => p.Permitido && acciones.Contains(p.Accion)))
            return;

        var accion = permitidas.FirstOrDefault(p => p.Accion == acciones[0]);
        log.LogWarning("Permiso denegado: usuario {Usuario} intentó {Acciones}", idUsuario, string.Join(" | ", acciones));
        contexto.Result = Denegar(accion is null
            ? $"La acción \"{acciones[0]}\" no está configurada en el sistema."
            : $"No tiene permiso para: {accion.AccionLabel}.");
    }

    /// <summary>Invalida la caché de un usuario (por ejemplo, al cambiarle el rol o el área).</summary>
    public static void Invalidar(IMemoryCache cache, long idUsuario) => cache.Remove($"acciones:{idUsuario}");

    private static RequierePermisoAttribute? ObtenerRequisito(AuthorizationFilterContext c)
    {
        if (c.ActionDescriptor is not ControllerActionDescriptor d) return null;
        return d.MethodInfo.GetCustomAttributes(typeof(RequierePermisoAttribute), true).Cast<RequierePermisoAttribute>().FirstOrDefault()
            ?? d.ControllerTypeInfo.GetCustomAttributes(typeof(RequierePermisoAttribute), true).Cast<RequierePermisoAttribute>().FirstOrDefault();
    }

    /// <summary>Catálogos editables desde la app: cada uno tiene su acción.</summary>
    private static string AccionDeCatalogo(string? descripcion) => (descripcion ?? "").ToUpperInvariant() switch
    {
        "AREA_USUARIO"                                                                         => "catalogo_area_usuario",
        "TIPO_SUMINISTRO" or "SUBTIPO_SUMINISTRO" or "MARCA_SUMINISTRO" or "MODELO_SUMINISTRO" => "catalogo_suministro",
        "CONDICION_PAGO"                                                                       => "catalogo_condicion_pago",
        _                                                                                      => "catalogo_otro",
    };

    private static ObjectResult Denegar(string mensaje)
        => new(new RespuestaDto<object>(1, mensaje)) { StatusCode = StatusCodes.Status403Forbidden };
}
