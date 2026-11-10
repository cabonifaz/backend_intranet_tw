using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Configuracion;

/// <summary>
/// HU-90 Centro de Notificaciones — alertas operativas del Módulo 11 Control de Campo.
/// Cada <c>AlertasOperativas:IntervaloSegundos</c> (60 por defecto) ejecuta SP_GenerarAlertasOperativas, que calcula las alertas con
/// los mismos umbrales de la bandeja de seguimiento (GPS parado, pérdida de contacto, sin ingreso, sin iniciar, proximidad, incidente
/// crítico) y las guarda como notificación para los usuarios con seg_bandeja (una por alerta, técnico, servicio y día).
/// Se desactiva con <c>AlertasOperativas:Habilitado = false</c>. Con varias instancias, el SP usa GET_LOCK y solo corre una.
/// </summary>
public sealed class AlertasOperativasWorker(
    IServiceScopeFactory scopes,
    IConfiguration configuracion,
    ILogger<AlertasOperativasWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!bool.TryParse(configuracion["AlertasOperativas:Habilitado"], out var habilitado)) habilitado = true;
        if (!habilitado)
        {
            logger.LogInformation("Alertas operativas desactivadas (AlertasOperativas:Habilitado = false).");
            return;
        }

        var segundos = int.TryParse(configuracion["AlertasOperativas:IntervaloSegundos"], out var s) ? Math.Clamp(s, 30, 3600) : 60;

        // Pequeña espera inicial para no competir con el arranque de la API
        try { await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken); }
        catch (OperationCanceledException) { return; }

        using var temporizador = new PeriodicTimer(TimeSpan.FromSeconds(segundos));
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var casoDeUso   = scope.ServiceProvider.GetRequiredService<GenerarAlertasOperativasCasoDeUso>();
                var r = await casoDeUso.EjecutarAsync(stoppingToken);

                if (r.IdTipoMensaje != 2)
                    logger.LogWarning("Alertas operativas: {Mensaje}", r.Mensaje);
                else if (r.Datos is { Generadas: > 0 } d)
                    logger.LogInformation("Alertas operativas: {Generadas} notificaciones nuevas ({Alertas} alertas activas).", d.Generadas, d.Alertas);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error al generar las alertas operativas.");
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
