using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile — Notificaciones push ────────────────────────────────────────────────────────

/// <summary>La app registra el token de su teléfono al iniciar sesión. El usuario sale del token de sesión.</summary>
public class RegistrarDispositivoPushMovilCasoDeUso(IPushMovilRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, RegistrarDispositivoPushEntradaDto? entrada, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "No se pudo identificar al usuario."));

        var idDispositivo = entrada?.IdDispositivo?.Trim();
        var token         = entrada?.Token?.Trim();

        if (string.IsNullOrEmpty(idDispositivo) || idDispositivo.Length > 100)
            return Task.FromResult(new RespuestaDto<bool>(1, "Identificador de dispositivo no válido."));

        if (string.IsNullOrEmpty(token) || token.Length > 255
            || !(token.StartsWith("ExponentPushToken[", StringComparison.Ordinal) || token.StartsWith("ExpoPushToken[", StringComparison.Ordinal))
            || !token.EndsWith(']'))
            return Task.FromResult(new RespuestaDto<bool>(1, "Token de notificaciones no válido."));

        var plataforma = (entrada?.Plataforma ?? "android").Trim().ToLowerInvariant();
        return repositorio.RegistrarAsync(idUsuario,
            new RegistrarDispositivoPushEntradaDto(idDispositivo, token, plataforma is "android" or "ios" ? plataforma : "android"), ct);
    }
}

/// <summary>Al cerrar sesión la app da de baja su teléfono: sin sesión no llegan avisos.</summary>
public class QuitarDispositivoPushMovilCasoDeUso(IPushMovilRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, string? idDispositivo, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "No se pudo identificar al usuario."));

        var id = idDispositivo?.Trim();
        if (string.IsNullOrEmpty(id) || id.Length > 100)
            return Task.FromResult(new RespuestaDto<bool>(1, "Identificador de dispositivo no válido."));

        return repositorio.QuitarAsync(idUsuario, id, ct);
    }
}

/// <summary>
/// Envía a la bandeja de notificaciones del teléfono las notificaciones nuevas (las que detecta el worker). Cada una va solo a los teléfonos
/// con sesión de su destinatario. Los tokens que Expo dice que ya no existen se dan de baja.
/// </summary>
public class EnviarPushNotificacionesCasoDeUso(IPushMovilRepositorio repositorio, IEnviadorPushMovil enviador)
{
    private const int UsuariosPorConsulta = 500;
    private const int TokensPorBaja       = 100;

    public async Task<ResultadoEnvioPushDto> EjecutarAsync(IReadOnlyList<NotificacionNuevaDto> nuevas, CancellationToken ct = default)
    {
        var pendientes = nuevas.Where(n => !n.Fila.Leida && !n.Fila.Archivada).ToList();
        if (pendientes.Count == 0) return new ResultadoEnvioPushDto(0, [], null);

        // Teléfonos de cada destinatario (en grupos, el SP recibe la lista separada por comas)
        var dispositivos = new Dictionary<long, List<string>>();
        foreach (var grupo in pendientes.Select(n => n.IdUsuarioDestino).Distinct().Chunk(UsuariosPorConsulta))
        {
            var r = await repositorio.ObtenerDispositivosAsync(grupo, ct);
            if (r.IdTipoMensaje != 2 || r.Datos is null)
                return new ResultadoEnvioPushDto(0, [], r.Mensaje);

            foreach (var d in r.Datos)
            {
                if (!dispositivos.TryGetValue(d.IdUsuario, out var tokens))
                    dispositivos[d.IdUsuario] = tokens = [];
                if (!tokens.Contains(d.Token)) tokens.Add(d.Token);
            }
        }

        var mensajes = new List<MensajePushDto>();
        foreach (var n in pendientes)
        {
            if (!dispositivos.TryGetValue(n.IdUsuarioDestino, out var tokens)) continue;

            var titulo = string.IsNullOrWhiteSpace(n.Fila.Titulo) ? "Total Weight" : Recortar(n.Fila.Titulo, 100);
            var cuerpo = Recortar(n.Fila.Resumen ?? string.Empty, 160);
            foreach (var token in tokens)
                mensajes.Add(new MensajePushDto(token, titulo, cuerpo, n.Fila.IdNotificacion, n.Fila.Prioridad ?? "normal"));
        }

        if (mensajes.Count == 0) return new ResultadoEnvioPushDto(0, [], null);

        var resultado = await enviador.EnviarAsync(mensajes, ct);

        foreach (var lote in resultado.TokensInvalidos.Distinct().Chunk(TokensPorBaja))
            await repositorio.DarDeBajaAsync(lote, ct);

        return resultado;
    }

    private static string Recortar(string texto, int maximo)
    {
        var t = texto.Trim();
        return t.Length <= maximo ? t : t[..(maximo - 1)] + "…";
    }
}
