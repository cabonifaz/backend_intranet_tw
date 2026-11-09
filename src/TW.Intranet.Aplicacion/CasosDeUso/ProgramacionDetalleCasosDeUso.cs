using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-37 Detalle de la Programación y registro de la confirmación con el cliente (Sprint 5) ─────────────

/// <summary>
/// Validación de la respuesta del cliente. Desarrollo seguro: listas cerradas para canal y resultado (nada libre llega al SP),
/// identificador positivo, comentario con largo máximo y sin caracteres de control.
/// </summary>
internal static class EntradaRespuestaCliente
{
    internal const int MaxComentario = 300;

    private static readonly string[] Canales    = ["correo", "whatsapp", "llamada", "presencial"];
    private static readonly string[] Resultados = ["acepto", "pidio_reprogramar", "cancelo"];

    internal static (NuevaRespuestaCliente? Respuesta, string? Error) Normalizar(long idProgramacion, RegistrarRespuestaClienteDto? d)
    {
        if (idProgramacion <= 0)
            return (null, "Indica la programación.");
        if (d is null)
            return (null, "Indica el canal utilizado y el resultado de la comunicación con el cliente.");

        var canal = d.Canal?.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(canal))
            return (null, "Selecciona el canal utilizado: correo, WhatsApp, llamada o presencial.");
        if (!Canales.Contains(canal))
            return (null, "El canal no es válido: usa correo, whatsapp, llamada o presencial.");

        var resultado = d.Resultado?.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(resultado))
            return (null, "Selecciona el resultado: aceptó, pidió reprogramar o canceló.");
        if (!Resultados.Contains(resultado))
            return (null, "El resultado no es válido: usa acepto, pidio_reprogramar o cancelo.");

        var comentario = d.Comentario?.Trim();
        if (comentario is { Length: > MaxComentario })
            return (null, $"El comentario no puede superar {MaxComentario} caracteres.");
        if (comentario is not null && comentario.Any(c => char.IsControl(c) && c is not ('\n' or '\r' or '\t')))
            return (null, "El comentario contiene caracteres no válidos.");

        return (new NuevaRespuestaCliente(idProgramacion, canal, resultado, string.IsNullOrEmpty(comentario) ? null : comentario), null);
    }
}

/// <summary>
/// HU-37 Detalle de la Programación: datos, checklist de validación, alerta SSOMA sobrevenida, historial y respuestas del
/// cliente. Las acciones disponibles las calcula el SP con el usuario del token.
/// </summary>
public class ObtenerDetalleProgramacionCasoDeUso(IProgramacionDetalleRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleProgramacionDto>> EjecutarAsync(long idProgramacion, long idUsuario, CancellationToken ct = default)
        => idProgramacion <= 0
            ? Task.FromResult(new RespuestaDto<DetalleProgramacionDto>(1, "Indica la programación."))
            : repositorio.ObtenerDetalleAsync(idProgramacion, idUsuario, ct);
}

/// <summary>
/// HU-37 Registra la respuesta del cliente tras coordinar fuera del sistema. No envía nada al cliente. Si aceptó, la programación
/// pasa a PROGRAMADO; si pidió reprogramar o canceló, solo se indica el flujo siguiente (HU-38). Las reglas las valida el SP.
/// </summary>
public class RegistrarRespuestaClienteCasoDeUso(IProgramacionDetalleRepositorio repositorio)
{
    public Task<RespuestaDto<RespuestaClienteRegistradaDto>> EjecutarAsync(
        long idProgramacion, RegistrarRespuestaClienteDto? d, long idUsuario, CancellationToken ct = default)
    {
        var (respuesta, error) = EntradaRespuestaCliente.Normalizar(idProgramacion, d);
        return error is not null
            ? Task.FromResult(new RespuestaDto<RespuestaClienteRegistradaDto>(1, error))
            : repositorio.RegistrarRespuestaClienteAsync(respuesta!, idUsuario, ct);
    }
}
