using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>App Mobile HU-32 — «Alerta de campo»: el pedido de apoyo del técnico con la tabla del ensayo.</summary>
public class ObtenerAlertaCampoMovilCasoDeUso(IAlertasCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<AlertaCampoMovilDto>> EjecutarAsync(long idUsuario, long idNotificacion, CancellationToken ct = default)
        => idUsuario <= 0 || idNotificacion <= 0
            ? Task.FromResult(new RespuestaDto<AlertaCampoMovilDto>(1, "La alerta no existe o no es tuya."))
            : repositorio.ObtenerAlertaAsync(idUsuario, idNotificacion, ct);
}

/// <summary>App Mobile HU-32 — Decisión del jefe: llamar, pedir repetir el ensayo o indicar ajuste y nueva calibración.</summary>
public class AccionAlertaCampoMovilCasoDeUso(IAlertasCampoMovilRepositorio repositorio)
{
    public static readonly string[] Acciones = ["llamar", "repetir", "ajuste"];

    public Task<RespuestaDto<ContactoAlertaMovilDto>> EjecutarAsync(long idUsuario, long idNotificacion, string? accion, string? mensaje, CancellationToken ct = default)
    {
        var a = (accion ?? string.Empty).Trim().ToLowerInvariant();
        if (idUsuario <= 0 || idNotificacion <= 0) return Task.FromResult(new RespuestaDto<ContactoAlertaMovilDto>(1, "La alerta no existe o no es tuya."));
        if (!Acciones.Contains(a)) return Task.FromResult(new RespuestaDto<ContactoAlertaMovilDto>(1, "La acción no es válida."));
        var limpio = EntradaObjetivosMovil.Limpiar(mensaje);
        if (limpio is { Length: > 300 }) return Task.FromResult(new RespuestaDto<ContactoAlertaMovilDto>(1, "La indicación puede tener hasta 300 caracteres."));
        return repositorio.AccionAsync(idUsuario, idNotificacion, a, limpio, ct);
    }
}

/// <summary>App Mobile HU-32 — Técnicos cercanos de la misma especialidad y con SSOMA conforme, para reasignar el servicio.</summary>
public class ObtenerTecnicosReasignacionMovilCasoDeUso(IAlertasCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ReasignacionOsMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => idUsuario <= 0 || idOs <= 0
            ? Task.FromResult(new RespuestaDto<ReasignacionOsMovilDto>(1, "El servicio indicado no es válido."))
            : repositorio.ObtenerTecnicosAsync(idUsuario, idOs, ct);
}

/// <summary>App Mobile HU-32 — Reasigna el servicio a otro técnico (avisa a ambos).</summary>
public class ReasignarTecnicoMovilCasoDeUso(IAlertasCampoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ReasignadoMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idTecnico, CancellationToken ct = default)
        => idUsuario <= 0 || idOs <= 0 || idTecnico <= 0
            ? Task.FromResult(new RespuestaDto<ReasignadoMovilDto>(1, "Elige el técnico al que se reasigna el servicio."))
            : repositorio.ReasignarAsync(idUsuario, idOs, idTecnico, ct);
}

/// <summary>
/// App Mobile HU-32 — Registrar una incidencia de un servicio (tipo, severidad, impacto, descripción y foto opcional de la cámara) y, si se pide, escalarla.
/// El back valida y guarda la foto ANTES de llamar al SP y la borra si el SP no registra la incidencia.
/// </summary>
public class RegistrarIncidenciaCampoMovilCasoDeUso(IAlertasCampoMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoFotoBytes = 5 * 1024 * 1024;

    /// <summary>baja → 1 · media → 2 · alta → 3 · critica → 4 (NIVEL_ALERTA).</summary>
    public static int? NivelDe(string? severidad) => (severidad ?? string.Empty).Trim().ToLowerInvariant() switch
    {
        "baja" => 1,
        "media" => 2,
        "alta" => 3,
        "critica" or "crítica" => 4,
        _ => null,
    };

    public async Task<RespuestaDto<IncidenciaRegistradaMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, int idTipo, string? severidad, string? impacto, string? descripcion, bool escalar,
        Stream? foto, long tamanoFoto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "El servicio indicado no es válido.");
        if (idTipo <= 0) return new(1, "Selecciona el tipo de incidencia.");
        if (NivelDe(severidad) is not { } nivel) return new(1, "Selecciona la severidad.");
        var imp = (impacto ?? string.Empty).Trim().ToLowerInvariant();
        if (imp is not ("retrasa" or "detiene")) return new(1, "Selecciona el impacto en el servicio.");
        var desc = EntradaObjetivosMovil.Limpiar(descripcion);
        if (desc is null || desc.Length < 3) return new(1, "Escribe la descripción de la incidencia (mínimo 3 caracteres).");
        if (desc.Length > 1000) return new(1, "La descripción puede tener hasta 1000 caracteres.");

        string? ruta = null;
        if (foto is not null && tamanoFoto > 0)
        {
            if (tamanoFoto > TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 5 MB.");
            using var buffer = new MemoryStream();
            await foto.CopyToAsync(buffer, ct);
            if (buffer.Length == 0 || buffer.Length > TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 5 MB.");
            if (!RegistrarDemoraMovilCasoDeUso.EsJpeg(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 3))))
                return new(1, "La foto debe ser una imagen JPEG tomada con la cámara.");
            ruta = $"incidencias/{idOs}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
            buffer.Position = 0;
            await almacen.GuardarAsync(ruta, buffer, ct);
        }

        var r = await repositorio.RegistrarIncidenciaAsync(idUsuario, idOs, idTipo, nivel, imp, desc, ruta, escalar, ct);
        if (r.IdTipoMensaje != 2 && ruta is not null) await almacen.EliminarAsync(ruta, CancellationToken.None);
        return r;
    }
}
