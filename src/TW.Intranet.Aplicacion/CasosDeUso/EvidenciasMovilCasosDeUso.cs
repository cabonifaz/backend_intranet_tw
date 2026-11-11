using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-11 / HU-12 / HU-13 — Registro fotográfico, evidencia forzada y microvideo de encendido ──────────

/// <summary>Panel de las 9 evidencias del equipo con su estado y el avance "N de 9 completas".</summary>
public class ObtenerEvidenciasMovilCasoDeUso(IEvidenciasMovilRepositorio repositorio)
{
    public Task<RespuestaDto<EvidenciasMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<EvidenciasMovilDto>(1, "Servicio o equipo no encontrado."))
            : repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
}

/// <summary>Lo que llega de la app al capturar una evidencia (los números como texto con punto decimal).</summary>
public record CapturaEvidenciaMovilDto(
    string? Codigo, int Pagina, decimal? Latitud, decimal? Longitud, decimal? Precision, DateTime? CapturadoUtc, decimal? DuracionSeg, string? QrTexto);

/// <summary>
/// El técnico captura una evidencia con la cámara de la app. El back valida el archivo (JPEG de la cámara; video MP4 de 3 a 5 s para el encendido),
/// lo guarda, lo valida con IA (Gemini; sin IA queda "omitida" y no bloquea) y registra el intento con el SP, que decide el resultado final
/// (placa que no coincide con el equipo, QR de otro equipo…). La toma rechazada se conserva: si el técnico la fuerza (HU-12) esa es la que queda.
/// </summary>
public class RegistrarEvidenciaMovilCasoDeUso(IEvidenciasMovilRepositorio repositorio, IValidadorEvidenciaIa ia, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoFotoBytes = 6 * 1024 * 1024;
    public const long TamanoMaximoVideoBytes = 15 * 1024 * 1024;
    public static readonly IReadOnlySet<string> Codigos = new HashSet<string>
        { "placa", "inicial", "encendido", "desmontaje", "abierto", "prueba", "final", "informe", "qr" };

    /// <summary>MP4 / MOV: la caja "ftyp" va en los bytes 4 a 7.</summary>
    public static bool EsMp4(ReadOnlySpan<byte> inicio) =>
        inicio.Length >= 8 && inicio[4] == (byte)'f' && inicio[5] == (byte)'t' && inicio[6] == (byte)'y' && inicio[7] == (byte)'p';

    /// <summary>Valida lo que llega; null si está bien, o el mensaje para el técnico.</summary>
    public static string? Validar(CapturaEvidenciaMovilDto? d)
    {
        if (d is null) return "Datos incompletos.";
        var codigo = (d.Codigo ?? string.Empty).Trim().ToLowerInvariant();
        if (!Codigos.Contains(codigo)) return "La evidencia no existe en el panel.";
        if (d.Pagina < 1 || d.Pagina > 10) return "El informe admite hasta 10 hojas.";
        if (d.Latitud is { } la && (la is < -90m or > 90m) || d.Longitud is { } lo && (lo is < -180m or > 180m)) return "La ubicación GPS no es válida.";
        if (d.Precision is < 0m or > 5000m) return "La precisión del GPS no es válida.";
        if (codigo == "encendido" && (d.DuracionSeg is null || d.DuracionSeg < 2.5m || d.DuracionSeg > 5.5m)) return "El microvideo debe durar de 3 a 5 segundos.";
        if (codigo == "qr" && (EntradaObjetivosMovil.Limpiar(d.QrTexto) is not { Length: <= 300 })) return "El código leído no es válido.";
        return null;
    }

    private static async Task<(byte[]? Bytes, string? Error)> LeerAsync(Stream? s, long tamano, long maximo, string que, CancellationToken ct)
    {
        if (s is null || tamano <= 0) return (null, $"Falta {que}.");
        if (tamano > maximo) return (null, $"{char.ToUpper(que[0])}{que[1..]} no puede superar los {maximo / 1024 / 1024} MB.");
        using var m = new MemoryStream();
        await s.CopyToAsync(m, ct);
        if (m.Length == 0) return (null, $"{char.ToUpper(que[0])}{que[1..]} está vacío.");
        if (m.Length > maximo) return (null, $"{char.ToUpper(que[0])}{que[1..]} no puede superar los {maximo / 1024 / 1024} MB.");
        return (m.ToArray(), null);
    }

    public async Task<RespuestaDto<ResultadoEvidenciaMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, CapturaEvidenciaMovilDto? d, Stream? archivo, long tamanoArchivo, Stream? cuadro, long tamanoCuadro, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Servicio o equipo no encontrado.");
        if (Validar(d) is { } error) return new(1, error);
        var codigo = d!.Codigo!.Trim().ToLowerInvariant();
        var qr = codigo == "qr";
        var video = codigo == "encendido";

        // Acceso y datos del equipo antes de gastar IA (el SP vuelve a validar todo al guardar)
        var panel = await repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
        if (panel.IdTipoMensaje != 2 || panel.Datos is null) return new(panel.IdTipoMensaje, panel.Mensaje);
        var cab = panel.Datos.Cabecera;
        if (!cab.PuedeRegistrar) return new(1, cab.Estado == "pausado" ? "El equipo está pausado: reanúdalo para registrar evidencias." : "Para registrar evidencias el equipo debe estar en ejecución.");

        string? rutaArchivo = null, rutaCuadro = null;
        var ia0 = new ResultadoValidacionEvidenciaIa("omitida", null, null);
        if (!qr)
        {
            // Foto JPEG de la cámara; en el encendido, un MP4 más el cuadro (JPEG) que analiza la IA
            var principal = await LeerAsync(archivo, tamanoArchivo, video ? TamanoMaximoVideoBytes : TamanoMaximoFotoBytes, video ? "el video" : "la foto", ct);
            if (principal.Error is not null) return new(1, principal.Error);
            byte[] imagen;
            if (video)
            {
                if (!EsMp4(principal.Bytes!)) return new(1, "El video debe ser un MP4 grabado con la cámara.");
                var c = await LeerAsync(cuadro, tamanoCuadro, TamanoMaximoFotoBytes, "el cuadro del video", ct);
                if (c.Error is not null) return new(1, c.Error);
                if (!RegistrarDemoraMovilCasoDeUso.EsJpeg(c.Bytes!.AsSpan(0, 3))) return new(1, "El cuadro del video debe ser una imagen JPEG.");
                imagen = c.Bytes!;
                var rc = $"evidencias/{idOs}/{idOsEquipo}/{codigo}_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}_cuadro.jpg";
                await almacen.GuardarAsync(rc, new MemoryStream(imagen), ct);
                rutaCuadro = rc;
                rutaArchivo = $"evidencias/{idOs}/{idOsEquipo}/{codigo}_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.mp4";
                await almacen.GuardarAsync(rutaArchivo, new MemoryStream(principal.Bytes!), ct);
            }
            else
            {
                if (!RegistrarDemoraMovilCasoDeUso.EsJpeg(principal.Bytes!.AsSpan(0, 3))) return new(1, "La foto debe ser una imagen JPEG tomada con la cámara.");
                imagen = principal.Bytes!;
                rutaArchivo = $"evidencias/{idOs}/{idOsEquipo}/{codigo}_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
                await almacen.GuardarAsync(rutaArchivo, new MemoryStream(imagen), ct);
            }

            try { ia0 = await ia.ValidarAsync(new SolicitudValidacionEvidenciaIa(codigo, imagen, cab.Marca, cab.Modelo, cab.NumeroSerie), ct); }
            catch (Exception) when (!ct.IsCancellationRequested) { ia0 = new("omitida", "La IA no estuvo disponible.", null); }
        }

        var r = await repositorio.RegistrarAsync(idUsuario, idOs, idOsEquipo, codigo, codigo == "informe" ? d.Pagina : 1, rutaArchivo, rutaCuadro, video ? d.DuracionSeg : null,
            d.Latitud, d.Longitud, d.Precision, d.CapturadoUtc, qr ? EntradaObjetivosMovil.Limpiar(d.QrTexto) : null, ia0, ct);

        // Si el SP no la registró no deben quedar archivos huérfanos
        if (r.IdTipoMensaje != 2)
        {
            if (rutaArchivo is not null) await almacen.EliminarAsync(rutaArchivo, CancellationToken.None);
            if (rutaCuadro is not null) await almacen.EliminarAsync(rutaCuadro, CancellationToken.None);
        }
        return r;
    }
}

/// <summary>HU-12 — el técnico acepta a la fuerza una foto rechazada por la IA, solo con un motivo escrito (3 a 300 caracteres).</summary>
public class ForzarEvidenciaMovilCasoDeUso(IEvidenciasMovilRepositorio repositorio)
{
    public const int MinMotivo = 3;
    public const int MaxMotivo = 300;

    public async Task<RespuestaDto<EvidenciasMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, long idEvidencia, PeticionForzarEvidenciaMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0 || idEvidencia <= 0) return new(1, "Evidencia no encontrada.");
        var motivo = EntradaObjetivosMovil.Limpiar(d?.Motivo);
        if (motivo is null || motivo.Length < MinMotivo) return new(1, $"Escribe el motivo por el que aceptas la foto (mínimo {MinMotivo} caracteres).");
        if (motivo.Length > MaxMotivo) return new(1, $"El motivo puede tener hasta {MaxMotivo} caracteres.");

        var r = await repositorio.ForzarAsync(idUsuario, idOs, idOsEquipo, idEvidencia, motivo, ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);
        var panel = await repositorio.ObtenerAsync(idUsuario, idOs, idOsEquipo, ct);
        return new(2, r.Mensaje, panel.IdTipoMensaje == 2 ? panel.Datos : null);
    }
}

/// <summary>Abre el archivo de una evidencia (o su cuadro) para mostrarla; solo si es de una OS del técnico.</summary>
public class ObtenerArchivoEvidenciaMovilCasoDeUso(IEvidenciasMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? TipoContenido, string? Mensaje)> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, long idEvidencia, bool cuadro, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0 || idEvidencia <= 0) return (null, null, "Evidencia no encontrada.");
        var r = await repositorio.ObtenerArchivoAsync(idUsuario, idOs, idOsEquipo, idEvidencia, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return (null, null, r.Mensaje);

        var ruta = cuadro && r.Datos.RutaCuadro is not null ? r.Datos.RutaCuadro : r.Datos.Ruta;
        var s = await almacen.AbrirLecturaAsync(ruta, ct);
        if (s is null) return (null, null, "El archivo ya no está disponible.");
        return (s, ruta.EndsWith(".mp4", StringComparison.OrdinalIgnoreCase) ? "video/mp4" : "image/jpeg", null);
    }
}
