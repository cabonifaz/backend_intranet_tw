using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-08 / HU-09 — Trabajo en el equipo y variables ambientales ────────────────────

/// <summary>
/// "Trabajo en el equipo": cabecera (servicio, equipo, tipo de orden OS/OM según la RQ, tiempos) y las 5 etapas con su estado.
/// El Hard Stop, el estado del equipo y el bloqueo de "Ensayos y Calibración" los decide el SP.
/// </summary>
public class ObtenerTrabajoEquipoMovilCasoDeUso(ITrabajoEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<TrabajoEquipoMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<TrabajoEquipoMovilDto>(1, "Servicio o equipo no encontrado."))
            : repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
}

/// <summary>
/// HU-09 — registra temperatura (°C) y humedad (%) obligatorias y la procedencia ("N.I" por defecto). La fecha y la hora las pone el servidor.
/// Valida el rango y el largo; el SP valida el Hard Stop y que el equipo esté en ejecución. Devuelve el trabajo ya actualizado (con Ensayos habilitado).
/// </summary>
public class GuardarVariablesAmbientalesMovilCasoDeUso(ITrabajoEquipoMovilRepositorio repositorio)
{
    public const decimal TemperaturaMin = -20m, TemperaturaMax = 60m, HumedadMin = 0m, HumedadMax = 100m;
    public const int MaxProcedencia = 100;

    /// <summary>Valida lo que llega; null si está bien, o el mensaje para el técnico (los mismos del SP).</summary>
    public static string? Validar(PeticionVariablesAmbientalesMovilDto? d)
    {
        if (d is null) return "Datos incompletos.";
        if (d.Temperatura is not { } t) return "Ingresa la temperatura (°C).";
        if (d.Humedad is not { } h) return "Ingresa la humedad relativa (%).";
        if (t < TemperaturaMin || t > TemperaturaMax) return "La temperatura debe estar entre -20 y 60 °C.";
        if (h < HumedadMin || h > HumedadMax) return "La humedad relativa debe estar entre 0 y 100 %.";
        if (EntradaObjetivosMovil.Limpiar(d.Procedencia) is { Length: > MaxProcedencia }) return $"La procedencia puede tener hasta {MaxProcedencia} caracteres.";
        return null;
    }

    public async Task<RespuestaDto<TrabajoEquipoMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, PeticionVariablesAmbientalesMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Servicio o equipo no encontrado.");
        if (Validar(d) is { } error) return new(1, error);

        var r = await repositorio.GuardarVariablesAsync(idUsuario, idOs, idOsEquipo, Math.Round(d!.Temperatura!.Value, 2), Math.Round(d.Humedad!.Value, 2),
            EntradaObjetivosMovil.Limpiar(d.Procedencia), RegistrarLlegadaMovilCasoDeUso.CapturaUtc(d.CapturadoEn), ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);

        var trabajo = await repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
        return new(2, r.Mensaje, trabajo.IdTipoMensaje == 2 ? trabajo.Datos : null);
    }
}
