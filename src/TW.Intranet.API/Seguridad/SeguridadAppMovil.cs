using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Seguridad;

/// <summary>
/// App Mobile — Desarrollo seguro. Todo aplica SOLO a la app de campo; la intranet no cambia:
///   1. Límite de ingresos por IP (política "movil-ingreso", solo en api/movil/autenticacion/iniciar-sesion).
///   2. Alcance del token: el token de la app solo sirve en las rutas que usa la app, y el token
///      de la intranet no sirve en api/movil/*.
///   3. Cabeceras de seguridad y "no guardar en caché" en las respuestas de api/movil/*.
///   4. Respuestas de error sin detalles internos (el detalle va al log del servidor).
/// </summary>
public static class SeguridadAppMovil
{
    public const string PoliticaIngreso = "movil-ingreso";
    public const string MensajeErrorGenerico = "Ocurrió un problema en el servidor. Inténtalo nuevamente en unos minutos.";

    private static readonly PathString RutaApp = new("/api/movil");

    /// <summary>Rutas de la intranet que la app sí usa con su token (además de api/movil/*).</summary>
    private static readonly PathString[] RutasIntranetPermitidas =
    [
        new("/api/autenticacion/me"),
        new("/api/autenticacion/cambiar-contrasena"),
        new("/api/maestros/catalogos"),
    ];

    public static bool EsRutaApp(PathString ruta) => ruta.StartsWithSegments(RutaApp, StringComparison.OrdinalIgnoreCase);

    /// <summary>¿Puede el token de la app (claim canal = movil) usarse en esta ruta?</summary>
    public static bool EsRutaPermitidaTokenMovil(PathString ruta) =>
        EsRutaApp(ruta) || RutasIntranetPermitidas.Any(r => ruta.StartsWithSegments(r, StringComparison.OrdinalIgnoreCase));

    public static IServiceCollection AgregarSeguridadAppMovil(this IServiceCollection services, OpcionesSeguridadMovil opciones)
    {
        services.AddRateLimiter(o =>
        {
            o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            o.AddPolicy(PoliticaIngreso, contexto => RateLimitPartition.GetFixedWindowLimiter(
                IpCliente(contexto) ?? "sin-ip",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit          = Math.Max(1, opciones.IngresosPorMinutoPorIp),
                    Window               = TimeSpan.FromMinutes(1),
                    QueueLimit           = 0,
                    AutoReplenishment    = true,
                }));
            o.OnRejected = async (contexto, ct) =>
            {
                contexto.HttpContext.Response.Headers.RetryAfter = "60";
                await contexto.HttpContext.Response.WriteAsJsonAsync(
                    new RespuestaDto<object>(1, "Demasiados intentos de ingreso desde esta red. Espera un minuto y vuelve a intentarlo."), ct);
            };
        });
        return services;
    }

    /// <summary>Cabeceras de seguridad para las respuestas de api/movil/* (no toca las de la intranet).</summary>
    public static IApplicationBuilder UsarCabecerasSeguridadAppMovil(this IApplicationBuilder app) =>
        app.Use(async (contexto, siguiente) =>
        {
            if (EsRutaApp(contexto.Request.Path))
            {
                contexto.Response.OnStarting(() =>
                {
                    var h = contexto.Response.Headers;
                    h["X-Content-Type-Options"]  = "nosniff";
                    h["X-Frame-Options"]         = "DENY";
                    h["Referrer-Policy"]         = "no-referrer";
                    h["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'";
                    h["Cache-Control"]           = "no-store";
                    h["Pragma"]                  = "no-cache";
                    return Task.CompletedTask;
                });
            }
            await siguiente(contexto);
        });

    /// <summary>
    /// IP del cliente. Detrás del proxy (Railway/Render) se toma la ÚLTIMA IP de X-Forwarded-For,
    /// que es la que agrega el proxy; las anteriores las puede inventar el cliente.
    /// Solo se aceptan IP válidas (evita guardar texto arbitrario en la BD).
    /// </summary>
    public static string? IpCliente(HttpContext contexto)
    {
        var reenviada = contexto.Request.Headers["X-Forwarded-For"].ToString()
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .LastOrDefault();

        if (reenviada is not null && IPAddress.TryParse(reenviada, out var ip))
            return ip.ToString();

        return contexto.Connection.RemoteIpAddress?.ToString();
    }

    /// <summary>Texto seguro para el log: sin saltos de línea (evita falsificar líneas del log) y corto.</summary>
    public static string ParaLog(string? texto)
    {
        if (string.IsNullOrEmpty(texto)) return "-";
        var limpio = new string(texto.Where(c => !char.IsControl(c)).ToArray());
        return limpio.Length > 60 ? limpio[..60] + "…" : limpio;
    }
}

/// <summary>Base de los controladores de la app: identifica al usuario y responde sin filtrar errores internos.</summary>
public abstract class ControladorAppMovil(ILogger logger) : Microsoft.AspNetCore.Mvc.ControllerBase
{
    protected long IdUsuarioActual =>
        long.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? User.FindFirst("sub")?.Value,
                      out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400 (regla de negocio), 3 → 500 con mensaje genérico; el detalle solo va al log.</summary>
    protected Microsoft.AspNetCore.Mvc.IActionResult Responder<T>(RespuestaDto<T> r, int codigoRegla = StatusCodes.Status400BadRequest)
    {
        switch (r.IdTipoMensaje)
        {
            case 2:
                return Ok(r);
            case 1:
                return StatusCode(codigoRegla, r);
            default:
                logger.LogError("App móvil: error en {Ruta} (usuario {IdUsuario}): {Detalle}",
                                HttpContext.Request.Path.Value, IdUsuarioActual, SeguridadAppMovil.ParaLog(r.Mensaje));
                return StatusCode(StatusCodes.Status500InternalServerError,
                                  new RespuestaDto<T>(3, SeguridadAppMovil.MensajeErrorGenerico));
        }
    }
}
