using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-05 — Registro de demoras en ruta ─────────────────────────────────────────

/// <summary>Contexto de la pantalla "Registrar demora": qué tipos se pueden registrar, las horas y las demoras ya hechas.</summary>
public class ObtenerDemorasMovilCasoDeUso(IDemorasMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ContextoDemorasMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return Task.FromResult(new RespuestaDto<ContextoDemorasMovilDto>(1, "Servicio no encontrado o no asignado a tu usuario."));

        return repositorio.ObtenerAsync(idUsuario, idOs, ct);
    }
}

/// <summary>
/// El técnico reporta una demora (llegar a planta o ingreso a planta). Valida los datos y la foto, guarda la foto en el almacenamiento
/// de archivos y llama al SP, que valida el estado del servicio, recalcula las horas y avisa a Operaciones.
/// La foto es opcional, solo JPEG tomado con la cámara (hasta 5 MB). Si el SP rechaza la demora, la foto no queda guardada.
/// </summary>
public class RegistrarDemoraMovilCasoDeUso(IDemorasMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoFotoBytes = 5 * 1024 * 1024;
    public const int  MinMinutos = 1;
    public const int  MaxMinutos = 480;
    public const int  MaxDescripcion = 500;

    public static readonly IReadOnlySet<string> Tipos = new HashSet<string> { "llegada", "ingreso" };

    /// <summary>Valida los datos que llegan; null si están bien, o el mensaje para el técnico.</summary>
    public static string? Validar(NuevaDemoraMovilDto? d)
    {
        if (d is null) return "Datos incompletos.";
        if (!Tipos.Contains((d.Tipo ?? string.Empty).Trim().ToLowerInvariant()))
            return "Elige dónde se presenta la demora: llegar a planta o ingreso a planta.";
        if (d.IdMotivo <= 0) return "Selecciona el tipo de demora.";
        if (d.DuracionMinutos < MinMinutos || d.DuracionMinutos > MaxMinutos)
            return $"La duración estimada debe estar entre {MinMinutos} y {MaxMinutos} minutos.";
        if ((d.Descripcion ?? string.Empty).Trim().Length > MaxDescripcion)
            return $"La descripción puede tener hasta {MaxDescripcion} caracteres.";
        if (d.Latitud is null || d.Longitud is null
            || d.Latitud < -90 || d.Latitud > 90 || d.Longitud < -180 || d.Longitud > 180
            || (d.Latitud == 0 && d.Longitud == 0))
            return "La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.";
        if (d.PrecisionMetros is < 0 or > 5000)
            return "La precisión del GPS no es válida.";
        return null;
    }

    /// <summary>La firma de un JPEG empieza con FF D8 FF (no basta con la extensión ni con lo que diga el teléfono).</summary>
    public static bool EsJpeg(ReadOnlySpan<byte> inicio) => inicio.Length >= 3 && inicio[0] == 0xFF && inicio[1] == 0xD8 && inicio[2] == 0xFF;

    public async Task<RespuestaDto<ResultadoDemoraMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, NuevaDemoraMovilDto? demora, Stream? foto, long tamanoFoto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, "Servicio no encontrado o no asignado a tu usuario.");

        var error = Validar(demora);
        if (error is not null) return new(1, error);
        var limpia = demora! with
        {
            Tipo        = demora.Tipo!.Trim().ToLowerInvariant(),
            Descripcion = LimpiarTexto(demora.Descripcion),
        };

        // Foto opcional: se valida y se guarda ANTES de registrar, y se borra si el SP rechaza la demora
        string? ruta = null;
        if (foto is not null && tamanoFoto > 0)
        {
            if (tamanoFoto > TamanoMaximoFotoBytes)
                return new(1, "La foto no puede superar los 5 MB.");

            using var buffer = new MemoryStream();
            await foto.CopyToAsync(buffer, ct);
            if (buffer.Length == 0) return new(1, "La foto está vacía.");
            if (buffer.Length > TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 5 MB.");
            if (!EsJpeg(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 3))))
                return new(1, "La foto debe ser una imagen JPEG tomada con la cámara.");

            ruta = $"demoras/{idOs}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
            buffer.Position = 0;
            await almacen.GuardarAsync(ruta, buffer, ct);
        }

        var r = await repositorio.RegistrarAsync(idUsuario, idOs, limpia.Tipo!, limpia, ruta, ct);

        // Si no se registró (o ya existía la misma demora y no usó la foto), no dejar archivos huérfanos
        if (ruta is not null && r.IdTipoMensaje != 2)
            await almacen.EliminarAsync(ruta, CancellationToken.None);

        return r;
    }

    /// <summary>Quita caracteres de control (menos el salto de línea) y recorta; vacío = sin descripción.</summary>
    internal static string? LimpiarTexto(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var limpio = new string(texto.Where(c => !char.IsControl(c) || c == '\n').ToArray()).Trim();
        return limpio.Length == 0 ? null : limpio;
    }
}
