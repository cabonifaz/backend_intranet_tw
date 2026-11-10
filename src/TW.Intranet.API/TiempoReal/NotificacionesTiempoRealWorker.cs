using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.API.TiempoReal;

/// <summary>
/// HU-90 parte 2 — Emite "notificacion.creada" sin tocar los ~40 SPs que insertan en notificacion.
/// Cada <c>TiempoReal:IntervaloSegundos</c> (3 por defecto) pide a SP_ObtenerNotificacionesNuevas las filas con id mayor al último
/// revisado y envía cada una al grupo user_{destinatario}, con el contador absoluto de no leídas.
/// Para no perder filas cuyo COMMIT llegó después que otras con id mayor (SPs con transacción larga), vuelve a pedir una ventana de
/// <see cref="Ventana"/> hacia atrás y descarta las que ya emitió. Al arrancar parte del último id (no reenvía lo antiguo; el front
/// se resincroniza con GET api/notificaciones/resumen al conectar o reconectar).
/// Se desactiva con <c>TiempoReal:Habilitado = false</c>.
/// </summary>
public sealed class NotificacionesTiempoRealWorker(
    IServiceScopeFactory scopes,
    INotificadorTiempoReal notificador,
    IConfiguration configuracion,
    ILogger<NotificacionesTiempoRealWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Ventana = TimeSpan.FromSeconds(60);
    private const int Limite = 2000;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!bool.TryParse(configuracion["TiempoReal:Habilitado"], out var habilitado)) habilitado = true;
        if (!habilitado)
        {
            logger.LogInformation("Tiempo real de notificaciones desactivado (TiempoReal:Habilitado = false).");
            return;
        }

        var segundos = int.TryParse(configuracion["TiempoReal:IntervaloSegundos"], out var s) ? Math.Clamp(s, 1, 60) : 3;

        try { await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken); }
        catch (OperationCanceledException) { return; }

        long? desde    = null;   // límite inferior de la consulta (el máximo visto hace ≥ Ventana)
        long  maxVisto = 0;
        var historial  = new Queue<(DateTime Momento, long Id)>();
        var emitidas   = new HashSet<long>();

        using var temporizador = new PeriodicTimer(TimeSpan.FromSeconds(segundos));
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var casoDeUso = scope.ServiceProvider.GetRequiredService<ObtenerNotificacionesNuevasCasoDeUso>();

                if (desde is null)
                {
                    var inicio = await casoDeUso.EjecutarAsync(-1, 1, stoppingToken);
                    if (inicio.IdTipoMensaje == 2 && inicio.Datos is { } d0)
                    {
                        desde = maxVisto = d0.UltimoId;
                        logger.LogInformation("Tiempo real de notificaciones activo desde el id {Id} (cada {Segundos} s).", d0.UltimoId, segundos);
                    }
                    else
                        logger.LogWarning("Tiempo real de notificaciones: {Mensaje}", inicio.Mensaje);
                    continue;
                }

                var r = await casoDeUso.EjecutarAsync(desde.Value, Limite, stoppingToken);
                if (r.IdTipoMensaje != 2 || r.Datos is null)
                {
                    logger.LogWarning("Tiempo real de notificaciones: {Mensaje}", r.Mensaje);
                    continue;
                }

                foreach (var n in r.Datos.Nuevas)
                    if (emitidas.Add(n.Fila.IdNotificacion))
                        await notificador.EnviarAUsuariosAsync([n.IdUsuarioDestino], EventosTiempoReal.NotificacionCreada,
                                                              new NotificacionCreadaEventoDto(n.Fila, n.NoLeidas), stoppingToken);

                var lleno = r.Datos.Nuevas.Count >= Limite;
                var tope  = lleno ? r.Datos.Nuevas.Max(n => n.Fila.IdNotificacion) : r.Datos.UltimoId;
                maxVisto  = Math.Max(maxVisto, tope);

                var ahora = DateTime.UtcNow;
                if (lleno)
                {
                    // Pico muy grande: se avanza sin ventana para no quedarse releyendo el mismo lote
                    logger.LogWarning("Tiempo real de notificaciones: más de {Limite} notificaciones en la ventana; se avanza hasta el id {Id}.", Limite, tope);
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
                emitidas.RemoveWhere(id => id <= limiteInferior);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error en el tiempo real de notificaciones.");
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
