using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-53 / HU-52 (Sprint 5) Foto de evidencia del Seguimiento Operativo ─────────────────────────────────────
// Subida: el Asistente adjunta la foto ANTES de registrar la demora/incidente (Modo 2) y recibe la ruta que luego envía como evidenciaUrl.
// Visualización: la foto de cualquier demora/incidencia/registro (técnico o Asistente) se descarga por la clave del registro, nunca por ruta libre.
// Desarrollo seguro: tipo real por la firma del archivo (no por la extensión ni el Content-Type del cliente), 5 MB máximo, nombre generado por el
// servidor, carpeta propia por OS y archivos servidos solo a usuarios con permiso sobre ese servicio.

/// <summary>Reglas de la foto de evidencia del Seguimiento Operativo.</summary>
public static partial class EvidenciaSeguimiento
{
    public const long TamanoMaximoBytes = 5 * 1024 * 1024;

    /// <summary>Ruta que genera la subida: /seguimiento/{idOs}/{yyyyMMddHHmmss}_{guid}.{jpg|png|webp}</summary>
    [GeneratedRegex(@"^/seguimiento/(?<os>[0-9]{1,18})/[0-9]{14}_[0-9a-f]{32}\.(jpg|png|webp)$")]
    private static partial Regex RutaSubida();

    /// <summary>JPEG, PNG o WEBP según los primeros bytes. Devuelve extensión y Content-Type, o null si no es una imagen permitida.</summary>
    public static (string Extension, string TipoContenido)? DetectarImagen(ReadOnlySpan<byte> b)
    {
        if (b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return ("jpg", "image/jpeg");
        if (b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A)
            return ("png", "image/png");
        if (b.Length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50)
            return ("webp", "image/webp");
        return null;
    }

    /// <summary>True si la ruta es una subida de evidencia de esta misma OS (el Asistente no puede apuntar a archivos de otra OS ni de otro módulo).</summary>
    public static bool EsRutaDeLaOs(string ruta, long idOs)
    {
        var m = RutaSubida().Match(ruta);
        return m.Success && m.Groups["os"].Value == idOs.ToString();
    }

    /// <summary>Content-Type de una foto guardada, por su extensión. Null si no es una imagen permitida (no se sirve).</summary>
    public static string? TipoPorExtension(string ruta) => Path.GetExtension(ruta).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" => "image/jpeg",
        ".png"            => "image/png",
        ".webp"           => "image/webp",
        _                 => null
    };

    /// <summary>Nombre original solo para mostrarlo: sin rutas ni caracteres de control, 100 caracteres como máximo.</summary>
    public static string NombreVisible(string? original, string extension)
    {
        var n = Path.GetFileName((original ?? "").Replace('\\', '/'));
        n = new string(n.Where(c => !char.IsControl(c) && c is not ('"' or '<' or '>' or '/' or ':')).ToArray()).Trim();
        if (n.Length == 0) n = $"evidencia.{extension}";
        return n.Length > 100 ? n[..100] : n;
    }
}

/// <summary>
/// Sube la foto de evidencia de un registro del Asistente (HU-53 Modo 2 Demora/Incidente). Devuelve la ruta para enviarla como evidenciaUrl en
/// POST /registros. Si la demora no llega a registrarse, la foto queda sin uso en la carpeta de la OS (no se expone: solo se sirve por la clave
/// de un registro que la referencie).
/// </summary>
public class SubirEvidenciaSeguimientoCasoDeUso(IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<EvidenciaSubidaDto>> EjecutarAsync(
        long idUsuario, long idOs, Stream? contenido, long tamano, string? nombreOriginal, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, "El servicio indicado no es válido.");
        if (contenido is null || tamano <= 0)
            return new(1, "Adjunta una foto en el campo \"archivo\".");
        if (tamano > EvidenciaSeguimiento.TamanoMaximoBytes)
            return new(1, "La foto no puede superar los 5 MB.");

        using var buffer = new MemoryStream();
        await contenido.CopyToAsync(buffer, ct);
        if (buffer.Length == 0) return new(1, "La foto está vacía.");
        if (buffer.Length > EvidenciaSeguimiento.TamanoMaximoBytes) return new(1, "La foto no puede superar los 5 MB.");

        var tipo = EvidenciaSeguimiento.DetectarImagen(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 12)));
        if (tipo is null)
            return new(1, "La evidencia debe ser una imagen JPG, PNG o WEBP.");

        var ruta = $"seguimiento/{idOs}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.{tipo.Value.Extension}";
        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);

        return new(2, "Archivo subido.", new EvidenciaSubidaDto(
            "/" + ruta, EvidenciaSeguimiento.NombreVisible(nombreOriginal, tipo.Value.Extension), buffer.Length, tipo.Value.TipoContenido));
    }
}

/// <summary>
/// Foto de evidencia de una demora/incidencia/registro del Asistente de la OS (clave d&lt;id&gt;, i&lt;id&gt; o a&lt;id&gt;), para el modal de detalle
/// y la tabla de Demoras (HU-52). Reutiliza el SP del detalle de la incidencia: valida permiso, alcance y que la clave sea de esa OS.
/// </summary>
public class ObtenerEvidenciaIncidenciaCasoDeUso(IDetalleServicioRutaRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idUsuario, long idOs, string? clave, CancellationToken ct = default)
    {
        var r = await new ObtenerIncidenciasServicioRutaCasoDeUso(repositorio).EjecutarAsync(idUsuario, idOs, string.IsNullOrWhiteSpace(clave) ? "?" : clave, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return new(r.IdTipoMensaje, r.Mensaje);

        var evidencia = r.Datos.Filas.FirstOrDefault()?.Evidencia?.Trim();
        if (string.IsNullOrEmpty(evidencia))
            return new(1, "Este registro no tiene foto de evidencia.");
        if (evidencia.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return new(1, "La evidencia de este registro es un enlace externo: ábrelo desde el detalle.");

        var ruta = evidencia.TrimStart('/');
        var tipo = EvidenciaSeguimiento.TipoPorExtension(ruta);
        if (tipo is null || ruta.Contains(".."))
            return new(1, "La evidencia de este registro no es una imagen.");

        var stream = await almacen.AbrirLecturaAsync(ruta, ct);
        return stream is null
            ? new(1, "No se encontró la foto de evidencia.")
            : new(2, "Éxito.", new ArchivoDescargaDto(stream, Path.GetFileName(ruta), tipo));
    }
}
