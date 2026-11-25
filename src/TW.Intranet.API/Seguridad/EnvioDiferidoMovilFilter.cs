using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Seguridad;

/// <summary>
/// App móvil sin señal — constancia de los envíos tardíos. Cuando la app reenvía algo de su cola manda la cabecera X-TW-Capturado-En (cuándo lo tomó el técnico);
/// si la escritura se aceptó (IdTipoMensaje 2), este filtro deja la constancia (SP_RegistrarEnvioDiferidoMovil) con el motivo y los intentos de las otras cabeceras.
/// Solo actúa en api/movil/*, en POST/PUT/DELETE y con la cabecera presente: los envíos en línea no cambian. NUNCA altera la respuesta ni la rompe: un fallo aquí solo se escribe en el log.
/// </summary>
public class EnvioDiferidoMovilFilter(RegistrarEnvioDiferidoMovilCasoDeUso registrar, ILogger<EnvioDiferidoMovilFilter> log) : IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext contexto, ActionExecutionDelegate siguiente)
    {
        var ejecutado = await siguiente();
        try
        {
            var http = contexto.HttpContext;
            if (!SeguridadAppMovil.EsRutaApp(http.Request.Path) || !ReglasEnvioDiferido.EsEscritura(http.Request.Method)) return;
            if (!ReglasEnvioDiferido.TryLeerCaptura(http.Request.Headers[ReglasEnvioDiferido.CabeceraCapturadoEn].ToString(), out var capturadoUtc)) return;
            if (!FueExitoso(ejecutado)) return;

            var usuario = http.User;
            if (!long.TryParse(usuario.FindFirstValue(ClaimTypes.NameIdentifier) ?? usuario.FindFirstValue("sub"), out var idUsuario) || idUsuario <= 0) return;

            var motivo   = http.Request.Headers[ReglasEnvioDiferido.CabeceraMotivo].ToString();
            var intentos = ReglasEnvioDiferido.LeerIntentos(http.Request.Headers[ReglasEnvioDiferido.CabeceraIntentos].ToString());
            var ruta     = http.Request.Path.Value ?? string.Empty;

            await registrar.EjecutarAsync(idUsuario, http.Request.Method, ruta, IdDeRuta(contexto, "idOs"), IdDeRuta(contexto, "idOsEquipo"),
                                          capturadoUtc, string.IsNullOrWhiteSpace(motivo) ? null : motivo, intentos, http.RequestAborted);
        }
        catch (Exception ex)
        {
            log.LogWarning(ex, "No se pudo dejar constancia de un envío tardío de la app móvil.");
        }
    }

    /// <summary>La escritura se aceptó: la respuesta es un sobre con IdTipoMensaje 2.</summary>
    private static bool FueExitoso(ActionExecutedContext ejecutado)
    {
        if (ejecutado.Exception is not null || ejecutado.Result is not ObjectResult { Value: { } valor }) return false;
        return valor.GetType().GetProperty("IdTipoMensaje")?.GetValue(valor) is 2;
    }

    private static long? IdDeRuta(ActionExecutingContext contexto, string clave) =>
        contexto.RouteData.Values.TryGetValue(clave, out var v) && long.TryParse(v?.ToString(), out var id) && id > 0 ? id : null;
}
