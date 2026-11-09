using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Adjuntos del requerimiento (observación 31/10): foto, video, correo, PDF, Office o texto.
/// Hasta 10 archivos por subida, 50 MB cada uno (el SP limita a 20 adjuntos por RQ).
/// </summary>
public class SubirAdjuntosRequerimientoCasoDeUso(IAdjuntosRequerimientoRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = 50L * 1024 * 1024;
    public const int  MaximoArchivos    = 10;

    private static readonly Dictionary<string, string> Tipos = new(StringComparer.OrdinalIgnoreCase)
    {
        [".pdf"]  = "application/pdf",
        [".png"]  = "image/png",
        [".jpg"]  = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".gif"]  = "image/gif",
        [".webp"] = "image/webp",
        [".heic"] = "image/heic",
        [".bmp"]  = "image/bmp",
        [".mp4"]  = "video/mp4",
        [".mov"]  = "video/quicktime",
        [".avi"]  = "video/x-msvideo",
        [".webm"] = "video/webm",
        [".3gp"]  = "video/3gpp",
        [".msg"]  = "application/vnd.ms-outlook",
        [".eml"]  = "message/rfc822",
        [".doc"]  = "application/msword",
        [".docx"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        [".xls"]  = "application/vnd.ms-excel",
        [".xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        [".ppt"]  = "application/vnd.ms-powerpoint",
        [".pptx"] = "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        [".txt"]  = "text/plain",
        [".csv"]  = "text/csv",
        [".zip"]  = "application/zip",
    };

    public record ArchivoEntrada(Stream Contenido, string? NombreArchivo, long TamanoBytes);

    public async Task<RespuestaDto<List<AdjuntoRequerimientoDto>>> EjecutarAsync(
        long idRequerimiento, IReadOnlyList<ArchivoEntrada> archivos, long idUsuario, CancellationToken ct = default)
    {
        if (idRequerimiento <= 0)            return new(1, "Requerimiento no válido.");
        if (archivos.Count == 0)             return new(1, "Seleccione al menos un archivo.");
        if (archivos.Count > MaximoArchivos) return new(1, $"Máximo {MaximoArchivos} archivos por subida.");

        foreach (var a in archivos)
        {
            var ext = Path.GetExtension(a.NombreArchivo ?? "");
            if (!Tipos.ContainsKey(ext))
                return new(1, $"\"{a.NombreArchivo}\": tipo de archivo no permitido (foto, video, correo, PDF, Office, texto o zip).");
            if (a.TamanoBytes <= 0 || a.TamanoBytes > TamanoMaximoBytes)
                return new(1, $"\"{a.NombreArchivo}\": el archivo debe pesar entre 1 byte y 50 MB.");
        }

        var resultado = new List<AdjuntoRequerimientoDto>();
        foreach (var a in archivos)
        {
            var validacion = await repositorio.RegistrarAsync(idRequerimiento, "", "", "", 0, idUsuario, true, ct);
            if (validacion.IdTipoMensaje != 2)
                return resultado.Count == 0
                    ? new(validacion.IdTipoMensaje, validacion.Mensaje)
                    : new(1, $"Se guardaron {resultado.Count} archivo(s). {validacion.Mensaje}", resultado);

            var ext    = Path.GetExtension(a.NombreArchivo!).ToLowerInvariant();
            var nombre = SubirAdjuntosSeguimientoCasoDeUso.NormalizarNombre(a.NombreArchivo!, ext);
            if (nombre.Length > 200) nombre = nombre[..(200 - ext.Length)] + ext;
            var ruta   = $"requerimientos/{idRequerimiento}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}{ext}";

            await almacen.GuardarAsync(ruta, a.Contenido, ct);
            var registro = await repositorio.RegistrarAsync(idRequerimiento, nombre, ruta, Tipos[ext], a.TamanoBytes, idUsuario, false, ct);
            if (registro.IdTipoMensaje != 2)
            {
                await almacen.EliminarAsync(ruta, CancellationToken.None);
                return new(registro.IdTipoMensaje, registro.Mensaje, resultado);
            }
            resultado.Add(new AdjuntoRequerimientoDto(registro.Datos, nombre, Tipos[ext], a.TamanoBytes, DateTime.Now, null));
        }
        return new(2, resultado.Count == 1 ? "Adjunto guardado." : $"{resultado.Count} adjuntos guardados.", resultado);
    }
}

/// <summary>Abre un adjunto del requerimiento para verlo o descargarlo.</summary>
public class ObtenerAdjuntoRequerimientoCasoDeUso(IAdjuntosRequerimientoRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idDocumento, long idUsuario, CancellationToken ct = default)
    {
        if (idDocumento <= 0) return new(1, "Adjunto no válido.");
        var ruta = await repositorio.ObtenerAsync(idDocumento, idUsuario, ct);
        if (ruta.IdTipoMensaje != 2 || ruta.Datos is null)
            return new(ruta.IdTipoMensaje, ruta.Mensaje);

        var contenido = await almacen.AbrirLecturaAsync(ruta.Datos.Ruta, ct);
        if (contenido is null)
            return new(1, "El adjunto está registrado pero no se encontró en el almacenamiento.");

        return new(2, ruta.Mensaje, new ArchivoDescargaDto(contenido, ruta.Datos.NombreArchivo, ruta.Datos.TipoContenido));
    }
}

/// <summary>Quita un adjunto del requerimiento (baja lógica; el archivo se conserva).</summary>
public class EliminarAdjuntoRequerimientoCasoDeUso(IAdjuntosRequerimientoRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idDocumento, long idUsuario, CancellationToken ct = default)
        => idDocumento <= 0
            ? Task.FromResult(new RespuestaDto<bool>(1, "Adjunto no válido."))
            : repositorio.EliminarAsync(idDocumento, idUsuario, ct);
}
