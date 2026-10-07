using System.Security.Cryptography;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ─────────────────────────────────────────────────────────────────────────────
// HU-87 — Carga real del PDF aprobado de Procedimientos.
// Cargarlo requiere la acción procedimiento_pdf_cargar (#4301, módulo "calidad"):
// por defecto área Calidad y administradores. Cualquier usuario autenticado puede verlo.
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Indica si el usuario actual puede cargar el PDF (para mostrar u ocultar la zona de carga).</summary>
public class ObtenerPermisoPdfProcedimientoCasoDeUso(IProcedimientosRepositorio repositorio)
{
    public Task<RespuestaDto<PermisoPdfProcedimientoDto>> EjecutarAsync(
        long idProcedimiento, long idUsuario, CancellationToken ct = default)
        => repositorio.ValidarCargaPdfAsync(Math.Max(idProcedimiento, 0), idUsuario, ct);
}

/// <summary>Valida, guarda en el almacenamiento y registra el PDF aprobado.</summary>
public class SubirPdfProcedimientoCasoDeUso(IProcedimientosRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = 10 * 1024 * 1024;

    public async Task<RespuestaDto<PdfProcedimientoDto>> EjecutarAsync(
        long idProcedimiento, Stream contenido, string? nombreArchivo, long tamanoBytes,
        long idUsuario, string? pcRegistro, CancellationToken ct = default)
    {
        if (idProcedimiento <= 0)
            return new RespuestaDto<PdfProcedimientoDto>(1, "Guarde el procedimiento antes de cargar el PDF.");
        if (tamanoBytes <= 0)
            return new RespuestaDto<PdfProcedimientoDto>(1, "Seleccione un archivo PDF.");
        if (tamanoBytes > TamanoMaximoBytes)
            return new RespuestaDto<PdfProcedimientoDto>(1, "El PDF no puede superar los 10 MB.");

        // Permiso y estado del procedimiento antes de escribir nada en disco
        var permiso = await repositorio.ValidarCargaPdfAsync(idProcedimiento, idUsuario, ct);
        if (permiso.IdTipoMensaje != 2 || permiso.Datos is null)
            return new RespuestaDto<PdfProcedimientoDto>(permiso.IdTipoMensaje, permiso.Mensaje);
        if (!permiso.Datos.PuedeSubirPdf)
            return new RespuestaDto<PdfProcedimientoDto>(1,
                permiso.Datos.Motivo ?? "No tiene permiso para cargar el PDF aprobado.");

        // Leer a memoria (máx. 10 MB) para validar la firma y calcular el hash
        using var buffer = new MemoryStream();
        await contenido.CopyToAsync(buffer, ct);

        if (buffer.Length == 0)
            return new RespuestaDto<PdfProcedimientoDto>(1, "Seleccione un archivo PDF.");
        if (buffer.Length > TamanoMaximoBytes)
            return new RespuestaDto<PdfProcedimientoDto>(1, "El PDF no puede superar los 10 MB.");

        var (esPdf, hash) = Analizar(buffer);
        if (!esPdf)
            return new RespuestaDto<PdfProcedimientoDto>(1, "El archivo no es un PDF válido.");

        var nombre = NormalizarNombre(nombreArchivo);
        var ruta   = $"procedimientos/{idProcedimiento}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.pdf";

        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);

        var registro = await repositorio.RegistrarPdfAsync(
            idProcedimiento, ruta, nombre, buffer.Length, hash, idUsuario, pcRegistro, ct);

        // Si la BD no lo registró, no dejar archivos huérfanos
        if (registro.IdTipoMensaje != 2)
            await almacen.EliminarAsync(ruta, CancellationToken.None);

        return registro;
    }

    /// <summary>Verifica la firma "%PDF-" (no basta con la extensión) y calcula el SHA-256.</summary>
    private static (bool EsPdf, string Hash) Analizar(MemoryStream buffer)
    {
        ReadOnlySpan<byte> bytes = buffer.GetBuffer().AsSpan(0, (int)buffer.Length);
        bool esPdf = bytes.StartsWith("%PDF-"u8);
        string hash = esPdf ? Convert.ToHexStringLower(SHA256.HashData(bytes)) : "";
        return (esPdf, hash);
    }

    private static string NormalizarNombre(string? nombreArchivo)
    {
        var nombre = Path.GetFileName(nombreArchivo ?? "").Trim();
        foreach (var c in Path.GetInvalidFileNameChars())
            nombre = nombre.Replace(c, '_');

        if (nombre.Length == 0)
            nombre = "procedimiento.pdf";
        if (!nombre.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase))
            nombre += ".pdf";
        if (nombre.Length > 255)
            nombre = nombre[..251] + ".pdf";

        return nombre;
    }
}

/// <summary>Abre el PDF aprobado para verlo o descargarlo.</summary>
public class ObtenerPdfProcedimientoCasoDeUso(IProcedimientosRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idProcedimiento, CancellationToken ct = default)
    {
        var ruta = await repositorio.ObtenerRutaPdfAsync(idProcedimiento, ct);
        if (ruta.IdTipoMensaje != 2 || ruta.Datos is null)
            return new RespuestaDto<ArchivoDescargaDto>(ruta.IdTipoMensaje, ruta.Mensaje);

        var contenido = await almacen.AbrirLecturaAsync(ruta.Datos.Ruta, ct);
        if (contenido is null)
            return new RespuestaDto<ArchivoDescargaDto>(1,
                "El PDF está registrado pero no se encontró en el almacenamiento. Vuelva a cargarlo.");

        return new RespuestaDto<ArchivoDescargaDto>(2, ruta.Mensaje,
            new ArchivoDescargaDto(contenido, ruta.Datos.NombreArchivo, "application/pdf"));
    }
}
