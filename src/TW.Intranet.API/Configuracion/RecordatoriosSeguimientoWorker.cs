using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Configuracion;

/// <summary>
/// Observaciones del cliente 2026-10-15 — Notificación anticipada de las acciones de seguimiento comercial.
/// Cada <c>Recordatorios:IntervaloSegundos</c> (60 por defecto) ejecuta SP_ProcesarRecordatoriosSeguimiento,
/// que crea la notificación en la plataforma para cada acción cuyo aviso ya venció
/// (fecha de la acción menos los minutos elegidos en el modal: 5, 10, 15, 20, 30 o 60).
/// Se desactiva con <c>Recordatorios:Habilitado = false</c>.
/// </summary>
public sealed class RecordatoriosSeguimientoWorker(
    IServiceScopeFactory scopes,
    IConfiguration configuracion,
    ILogger<RecordatoriosSeguimientoWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!bool.TryParse(configuracion["Recordatorios:Habilitado"], out var habilitado)) habilitado = true;
        if (!habilitado)
        {
            logger.LogInformation("Recordatorios de seguimiento desactivados (Recordatorios:Habilitado = false).");
            return;
        }

        var segundos = int.TryParse(configuracion["Recordatorios:IntervaloSegundos"], out var s) ? Math.Clamp(s, 15, 3600) : 60;

        // Pequeña espera inicial para no competir con el arranque de la API
        try { await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken); }
        catch (OperationCanceledException) { return; }

        using var temporizador = new PeriodicTimer(TimeSpan.FromSeconds(segundos));
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var casoDeUso   = scope.ServiceProvider.GetRequiredService<ProcesarRecordatoriosSeguimientoCasoDeUso>();
                var r = await casoDeUso.EjecutarAsync(stoppingToken);

                if (r.IdTipoMensaje != 2)
                    logger.LogWarning("Recordatorios de seguimiento: {Mensaje}", r.Mensaje);
                else if (r.Datos is { } d && (d.Enviados + d.Omitidos + d.Cancelados) > 0)
                    logger.LogInformation("Recordatorios de seguimiento: {Enviados} enviados, {Omitidos} omitidos, {Cancelados} cancelados.",
                                          d.Enviados, d.Omitidos, d.Cancelados);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error al procesar los recordatorios de seguimiento.");
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
