using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-06 — Llegada forzada ──────────────────────────────────────────────────────────

/// <summary>
/// El técnico, fuera del radio tras volver a capturar su ubicación (la app exige 5 veces), pide a Jefatura que le autorice registrar su llegada.
/// El usuario sale del token; el SP comprueba que la OS sea suya y esté en ruta, que de verdad esté fuera del rango y avisa al encargado del área.
/// </summary>
public class SolicitarLlegadaForzadaMovilCasoDeUso(ILlegadaForzadaRepositorio repositorio)
{
    public const int MaxMotivo = 500;

    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, long idOs, PeticionLlegadaForzadaDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return Task.FromResult(new RespuestaDto<bool>(1, EntradaLlegadaMovil.SinServicio));
        if (EntradaLlegadaMovil.Validar(d) is { } error) return Task.FromResult(new RespuestaDto<bool>(1, error));

        var motivo = SolicitarAutorizacionSalidaMovilCasoDeUso.Limpiar(d!.Motivo);
        if (motivo is { Length: > MaxMotivo })
            return Task.FromResult(new RespuestaDto<bool>(1, $"El motivo puede tener hasta {MaxMotivo} caracteres."));

        return repositorio.SolicitarAsync(idUsuario, idOs, Math.Round(d.Latitud!.Value, 7), Math.Round(d.Longitud!.Value, 7),
            Math.Round(d.PrecisionMetros!.Value, 1), Math.Clamp(d.Intentos ?? 0, 0, 1000), motivo, ct);
    }
}

/// <summary>Detalle de la solicitud de llegada forzada de una OS para el encargado (la más reciente; el SP filtra por su área).</summary>
public class ObtenerAprobacionLlegadaMovilCasoDeUso(ILlegadaForzadaRepositorio repositorio)
{
    public async Task<RespuestaDto<SolicitudLlegadaForzadaDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        const string noEncontrada = "No se encontró la solicitud de llegada o no corresponde a tu área.";
        if (idUsuario <= 0 || idOs <= 0) return new(1, noEncontrada);

        var r = await repositorio.ObtenerAsync(idUsuario, idOs, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        return r.Datos.FirstOrDefault() is { } s ? new(2, r.Mensaje, s) : new(1, noEncontrada);
    }
}

/// <summary>
/// El encargado autoriza la llegada (con una condición) o la rechaza (con un motivo): el texto es obligatorio, de 3 a 500 caracteres.
/// Solo después de aprobarla el técnico puede registrar la llegada fuera del radio (una vez).
/// </summary>
public class ResolverAprobacionLlegadaMovilCasoDeUso(ILlegadaForzadaRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idJefe, long idOs, ResolverAutorizacionSalidaDto? dto, CancellationToken ct = default)
    {
        if (idJefe <= 0 || idOs <= 0 || dto is null)
            return Task.FromResult(new RespuestaDto<bool>(1, "Datos incompletos."));

        var texto = SolicitarAutorizacionSalidaMovilCasoDeUso.Limpiar(dto.Comentario);
        if (texto is null || texto.Length < ResolverAprobacionSalidaMovilCasoDeUso.MinTexto)
            return Task.FromResult(new RespuestaDto<bool>(1, dto.Aprobar
                ? "Indica la condición con la que autorizas la llegada."
                : "Indica el motivo por el que no autorizas la llegada."));
        if (texto.Length > ResolverAprobacionSalidaMovilCasoDeUso.MaxTexto)
            return Task.FromResult(new RespuestaDto<bool>(1, $"El texto puede tener hasta {ResolverAprobacionSalidaMovilCasoDeUso.MaxTexto} caracteres."));

        return repositorio.ResolverAsync(idJefe, idOs, dto.Aprobar, texto, ct);
    }
}
