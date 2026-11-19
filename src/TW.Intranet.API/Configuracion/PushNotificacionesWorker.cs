using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Configuracion;

/// <summary>
/// App Mobile — Notificaciones push. Cada <c>PushMovil:IntervaloSegundos</c> (4 por defecto) pide a SP_ObtenerNotificacionesNuevas las filas con id
/// mayor al último revisado (las mismas que alimentan el tiempo real de la intranet: no se toca ninguno de los SPs que insertan en
/// <c>notificacion</c>) y las envía a la bandeja de notificaciones de los teléfonos con sesión de cada destinatario.
/// Para no perder filas cuyo COMMIT llegó después que otras con id mayor, vuelve a pedir una ventana de <see cref="Ventana"/> hacia atrás y
/// descarta las que ya envió. Al arrancar parte del último id: no reenvía lo antiguo.
/// Se desactiva con <c>PushMovil:Habilitado = false</c>.
/// </summary>
public sealed class PushNotificacionesWorker(
    IServiceScopeFactory scopes,
    IConfiguration configuracion,
    ILogger<PushNotificacionesWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Ventana = TimeSpan.FromSeconds(60);
    private const int Limite = 2000;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!bool.TryParse(configuracion["PushMovil:Habilitado"], out var habilitado)) habilitado = true;
        if (!habilitado)
        {
            logger.LogInformation("Notificaciones push de la app desactivadas (PushMovil:Habilitado = false).");
            return;
        }

        var segundos = int.TryParse(configuracion["PushMovil:IntervaloSegundos"], out var s) ? Math.Clamp(s, 2, 60) : 4;

        try { await Task.Delay(TimeSpan.FromSeconds(12), stoppingToken); }
        catch (OperationCanceledException) { return; }

        long? desde    = null;
        long  maxVisto = 0;
        var historial  = new Queue<(DateTime Momento, long Id)>();
        var enviadas   = new HashSet<long>();

        using var temporizador = new PeriodicTimer(TimeSpan.FromSeconds(segundos));
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var consulta = scope.ServiceProvider.GetRequiredService<ObtenerNotificacionesNuevasCasoDeUso>();

                if (desde is null)
                {
                    var inicio = await consulta.EjecutarAsync(-1, 1, stoppingToken);
                    if (inicio.IdTipoMensaje == 2 && inicio.Datos is { } d0)
                    {
                        desde = maxVisto = d0.UltimoId;
                        logger.LogInformation("Notificaciones push de la app activas desde el id {Id} (cada {Segundos} s).", d0.UltimoId, segundos);
                    }
                    else
                        logger.LogWarning("Notificaciones push de la app: {Mensaje}", inicio.Mensaje);
                    continue;
                }

                var r = await consulta.EjecutarAsync(desde.Value, Limite, stoppingToken);
                if (r.IdTipoMensaje != 2 || r.Datos is null)
                {
                    logger.LogWarning("Notificaciones push de la app: {Mensaje}", r.Mensaje);
                    continue;
                }

                var porEnviar = r.Datos.Nuevas.Where(n => enviadas.Add(n.Fila.IdNotificacion)).ToList();
                if (porEnviar.Count > 0)
                {
                    var envio = await scope.ServiceProvider.GetRequiredService<EnviarPushNotificacionesCasoDeUso>()
                                           .EjecutarAsync(porEnviar, stoppingToken);

                    if (envio.Enviados > 0)
                        logger.LogInformation("Notificaciones push de la app: {Enviados} enviadas ({Invalidos} teléfonos dados de baja).",
                                              envio.Enviados, envio.TokensInvalidos.Count);
                    if (!string.IsNullOrEmpty(envio.Error))
                        logger.LogWarning("Notificaciones push de la app: {Error}", envio.Error);
                }

                var lleno = r.Datos.Nuevas.Count >= Limite;
                var tope  = lleno ? r.Datos.Nuevas.Max(n => n.Fila.IdNotificacion) : r.Datos.UltimoId;
                maxVisto  = Math.Max(maxVisto, tope);

                var ahora = DateTime.UtcNow;
                if (lleno)
                {
                    logger.LogWarning("Notificaciones push de la app: más de {Limite} notificaciones en la ventana; se avanza hasta el id {Id}.", Limite, tope);
                    desde = tope;
                    historial.Clear();
                }
                else
                {
                    historial.Enqueue((ahora, maxVisto));
                    while (historial.Count > 0 && historial.Peek().Momento <= ahora - Ventana)
                        desde = historial.Dequeue().Id;
                }

                var limiteInferior = desde.Value;
                enviadas.RemoveWhere(id => id <= limiteInferior);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error en las notificaciones push de la app.");
            }
        }
        while (await EsperarAsync(temporizador, stoppingToken));
    }

    private static async Task<bool> EsperarAsync(PeriodicTimer temporizador, CancellationToken ct)
    {
        try { return await temporizador.WaitForNextTickAsync(ct); }
        catch (OperationCanceledException) { return false; }
    }
}
