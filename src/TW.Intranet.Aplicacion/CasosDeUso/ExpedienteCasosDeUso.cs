using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ══════════════════════ Expediente Digital (HU-29 a HU-34) ══════════════════════

/// <summary>Archivos que se suben al expediente: validación por extensión y firma, ruta y hash.</summary>
internal static class ArchivoExpediente
{
    /// <summary>Documentos internos (HU-31): PDF, DOCX, XLSX, PNG o JPG hasta 25 MB.</summary>
    public const long TamanoMaximoDocumento = 25L * 1024 * 1024;

    /// <summary>Evidencia de un bloqueo o excepción (HU-32): PDF, JPG o PNG hasta 10 MB.</summary>
    public const long TamanoMaximoEvidencia = 10L * 1024 * 1024;

    public static readonly string[] ExtensionesDocumento = [".pdf", ".docx", ".xlsx", ".png", ".jpg", ".jpeg"];
    public static readonly string[] ExtensionesEvidencia = [".pdf", ".png", ".jpg", ".jpeg"];

    public static string TipoContenido(string extension) => extension switch
    {
        ".pdf"  => "application/pdf",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".png"  => "image/png",
        ".jpg" or ".jpeg" => "image/jpeg",
        _       => "application/octet-stream",
    };

    /// <summary>Lee el archivo a memoria y valida tamaño, extensión y que el contenido corresponda a la extensión.</summary>
    public static async Task<(MemoryStream? Buffer, string? Extension, string? Error)> LeerAsync(
        Stream contenido, string? nombreArchivo, long tamano, long maximo, string[] permitidas, CancellationToken ct)
    {
        var extension = Path.GetExtension(nombreArchivo ?? "").ToLowerInvariant();
        if (!permitidas.Contains(extension))
            return (null, null, $"Formato no permitido. Use {string.Join(", ", permitidas.Select(e => e.TrimStart('.').ToUpperInvariant()).Distinct())}.");
        if (tamano <= 0) return (null, null, "El archivo está vacío.");
        if (tamano > maximo) return (null, null, $"El archivo supera el máximo de {maximo / (1024 * 1024)} MB.");

        var buffer = new MemoryStream();
        await contenido.CopyToAsync(buffer, ct);
        if (buffer.Length > maximo)
            return (null, null, $"El archivo supera el máximo de {maximo / (1024 * 1024)} MB.");

        if (!FirmaCorrecta(buffer.GetBuffer().AsSpan(0, (int)Math.Min(buffer.Length, 8)), extension))
            return (null, null, "El contenido del archivo no corresponde a su extensión.");

        buffer.Position = 0;
        return (buffer, extension, null);
    }

    private static bool FirmaCorrecta(ReadOnlySpan<byte> b, string extension) => extension switch
    {
        ".pdf"            => b.Length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46,   // %PDF
        ".png"            => b.Length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47,
        ".jpg" or ".jpeg" => b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF,
        ".docx" or ".xlsx" => b.Length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04,  // ZIP
        _ => false,
    };

    public static string Ruta(long idExpediente, string extension) =>
        $"expedientes/{idExpediente}/{DateTime.Now:yyyyMMddHHmmss}_{Guid.NewGuid():N}{extension}";

    public static string NormalizarNombre(string? nombreArchivo, string extension)
    {
        var nombre = NombreSeguro(Path.GetFileNameWithoutExtension(nombreArchivo ?? ""));
        if (nombre.Length == 0) nombre = "documento";
        if (nombre.Length > 200 - extension.Length) nombre = nombre[..(200 - extension.Length)];
        return nombre + extension;
    }

    /// <summary>
    /// Solo letras (con tildes), dígitos, espacio y . _ - ( ): sin separadores de ruta (/ \ :) ni "..", en cualquier
    /// sistema operativo. Evita rutas manipuladas en el ZIP de exportación (zip slip) y en los nombres de descarga.
    /// </summary>
    public static string NombreSeguro(string? texto)
    {
        var sb = new StringBuilder();
        foreach (var c in (texto ?? "").Trim())
            sb.Append(char.IsLetterOrDigit(c) || c is ' ' or '.' or '_' or '-' or '(' or ')' ? c : '_');
        var limpio = sb.ToString();
        while (limpio.Contains("..")) limpio = limpio.Replace("..", ".");
        return limpio.Trim(' ', '.');
    }

    /// <summary>Recorta y valida el largo de un texto opcional. Devuelve el error si supera el máximo.</summary>
    public static string? Largo(string? valor, int maximo, string campo) =>
        valor is not null && valor.Trim().Length > maximo ? $"{campo} no puede superar los {maximo} caracteres." : null;

    public static string Hash(MemoryStream buffer) =>
        Convert.ToHexString(SHA256.HashData(buffer.GetBuffer().AsSpan(0, (int)buffer.Length))).ToLowerInvariant();

    /// <summary>Abre un archivo del almacenamiento sin lanzar si la ruta no es válida (devuelve null).</summary>
    public static async Task<Stream?> AbrirAsync(IAlmacenArchivos almacen, string ruta, CancellationToken ct)
    {
        try { return await almacen.AbrirLecturaAsync(ruta, ct); }
        catch (InvalidOperationException) { return null; }
        catch (ArgumentException) { return null; }
    }
}

// ── HU-29 Bandeja ────────────────────────────────────────────────────────────

/// <summary>Bandeja: tarjetas de estados críticos, filas con la vinculación completa y opciones de los filtros.</summary>
public class ObtenerBandejaExpedientesCasoDeUso(IExpedienteRepositorio repositorio)
{
    private static readonly string[] Estados =
        ["", "abiertos", "todos", "activo", "listo_para_avanzar", "bloqueado", "con_excepcion", "sla_vencido", "pendiente_cierre", "cerrado"];

    public Task<RespuestaDto<BandejaExpedientesDto>> EjecutarAsync(FiltrosBandejaExpedientesDto f, long idUsuario, CancellationToken ct = default)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return Task.FromResult(new RespuestaDto<BandejaExpedientesDto>(1,
                "Estado no válido. Use abiertos, todos, activo, listo_para_avanzar, bloqueado, con_excepcion, sla_vencido, pendiente_cierre o cerrado."));

        var filtros = f with
        {
            Estado    = estado,
            Etapa     = string.IsNullOrWhiteSpace(f.Etapa) ? null : Recortar(f.Etapa.Trim().ToLowerInvariant(), 30),
            IdCliente = f.IdCliente is > 0 ? f.IdCliente : null,
            Area      = string.IsNullOrWhiteSpace(f.Area) ? null : Recortar(f.Area.Trim().ToLowerInvariant(), 40),
            Busqueda  = string.IsNullOrWhiteSpace(f.Busqueda) ? null : Recortar(f.Busqueda.Trim(), 100),
            Pagina    = Math.Max(1, f.Pagina),
            PorPagina = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina,
        };
        return repositorio.ObtenerBandejaAsync(filtros, idUsuario, ct);
    }

    private static string Recortar(string texto, int maximo) => texto.Length > maximo ? texto[..maximo] : texto;
}

// ── HU-30 Detalle, workflow y exportaciones ──────────────────────────────────

public class ObtenerDetalleExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<DetalleExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerDetalleAsync(idExpediente, idUsuario, ct);
}

public class ObtenerWorkflowExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<WorkflowExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<WorkflowExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerWorkflowAsync(idExpediente, idUsuario, ct);
}

/// <summary>Hojas de Excel del expediente (workflow e historial), compartidas por las exportaciones.</summary>
internal static class HojasExpediente
{
    private static string Estado(string estado) => estado switch
    {
        "completado" => "Completado", "en_curso" => "En curso", "bloqueado" => "Bloqueado",
        "pendiente"  => "Pendiente",  "cancelado" => "Cancelado", "no_aplica" => "No aplica",
        _ => estado,
    };

    public static HojaExcel Resumen(ResumenWorkflowExpedienteDto r) => new("Resumen", ["Dato", "Valor"],
    [
        ["Expediente", r.Numero], ["Cliente", r.RazonSocial], ["RUC", r.Ruc], ["Requerimiento", r.NumeroRq],
        ["Propuesta", r.Propuesta], ["Órdenes de compra", r.NumerosOc], ["Órdenes de servicio", r.NumerosOs],
        ["Órdenes de metrología", r.NumerosOm], ["Tipo de servicio", r.TipoServicio], ["Etapa actual", r.EtapaNombre],
        ["Estado", r.Estado.Replace('_', ' ')], ["Progreso (%)", r.Progreso], ["Exportado", DateTime.Now],
    ]);

    public static HojaExcel Workflow(IReadOnlyList<EtapaWorkflowDto> etapas) => new("Workflow",
        ["Etapa", "Estado", "Área", "Responsable", "Inicio", "Fin", "T. espera (h)", "T. proceso (h)", "SLA (h)", "Cumple SLA", "Resultado"],
        etapas.Select(e => (IReadOnlyList<object?>)
        [
            e.Nombre, Estado(e.Estado), e.AreaNombre, e.Responsable, e.Inicio, e.Fin, e.HorasEspera, e.HorasProceso,
            e.SlaHoras, e.CumpleSla is null ? null : e.CumpleSla.Value ? "Sí" : "No", e.Resultado,
        ]).ToList());

    public static HojaExcel Historial(IReadOnlyList<EventoExpedienteDto> eventos) => new("Historial",
        ["Fecha", "Evento", "Detalle", "Etapa", "Usuario", "Referencia"],
        eventos.Select(e => (IReadOnlyList<object?>)
            [e.Fecha, e.Titulo, e.Descripcion, e.EtapaNombre ?? e.Etapa, e.Usuario, e.Referencia]).ToList());
}

/// <summary>HU-30 — Exporta el workflow del expediente a Excel (resumen y detalle por etapa).</summary>
public class ExportarWorkflowExpedienteCasoDeUso(IExpedienteRepositorio repositorio, IGeneradorExcel excel)
{
    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        var w = await repositorio.ObtenerWorkflowAsync(idExpediente, idUsuario, ct);
        if (w.IdTipoMensaje != 2 || w.Datos is null) return new(w.IdTipoMensaje, w.Mensaje);

        var contenido = excel.Generar([HojasExpediente.Resumen(w.Datos.Resumen), HojasExpediente.Workflow(w.Datos.Etapas)]);
        return new(2, "Workflow exportado.", new ArchivoGeneradoDto(contenido, $"Workflow-{w.Datos.Resumen.Numero}.xlsx",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"));
    }
}

/// <summary>
/// HU-30 — Exporta el expediente completo en un ZIP: expediente.xlsx (resumen, workflow e historial) y los documentos
/// que el usuario puede ver, en una carpeta por categoría. Los PDF de las propuestas se generan en el momento.
/// Los archivos que no estén en el almacenamiento se listan en "pendientes.txt" en vez de fallar.
/// El ZIP se arma en un archivo temporal (no en memoria) que se borra solo al terminar la descarga.
/// </summary>
public class ExportarExpedienteCasoDeUso(
    IExpedienteRepositorio      repositorio,
    IGeneradorExcel             excel,
    IAlmacenArchivos            almacen,
    GenerarPdfPropuestaCasoDeUso pdfPropuesta)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");

        var w = await repositorio.ObtenerWorkflowAsync(idExpediente, idUsuario, ct);
        if (w.IdTipoMensaje != 2 || w.Datos is null) return new(w.IdTipoMensaje, w.Mensaje);
        var h = await repositorio.ObtenerHistorialAsync(idExpediente, new FiltrosHistorialExpedienteDto(), false, idUsuario, ct);
        if (h.IdTipoMensaje != 2 || h.Datos is null) return new(h.IdTipoMensaje, h.Mensaje);
        var archivos = await repositorio.ObtenerArchivosExportacionAsync(idExpediente, idUsuario, ct);
        if (archivos.IdTipoMensaje != 2 || archivos.Datos is null) return new(archivos.IdTipoMensaje, archivos.Mensaje);

        var numero = ArchivoExpediente.NombreSeguro(w.Datos.Resumen.Numero);
        var temporal = new FileStream(Path.Combine(Path.GetTempPath(), $"tw-exp-{Guid.NewGuid():N}.zip"), FileMode.CreateNew,
                                      FileAccess.ReadWrite, FileShare.None, 81920, FileOptions.DeleteOnClose | FileOptions.Asynchronous);
        try
        {
            using (var zip = new ZipArchive(temporal, ZipArchiveMode.Create, leaveOpen: true))
            {
                var libro = excel.Generar(
                [
                    HojasExpediente.Resumen(w.Datos.Resumen),
                    HojasExpediente.Workflow(w.Datos.Etapas),
                    HojasExpediente.Historial(h.Datos.Eventos),
                ]);
                await EscribirAsync(zip, $"{numero}/expediente.xlsx", libro, ct);

                var pendientes = new List<string>();
                var usados = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var a in archivos.Datos)
                {
                    var carpeta = Limpiar(a.Carpeta);
                    var nombre  = Limpiar(a.Version > 1 ? $"{Path.GetFileNameWithoutExtension(a.NombreArchivo)}-v{a.Version}{Path.GetExtension(a.NombreArchivo)}" : a.NombreArchivo);
                    var ruta    = Unico($"{numero}/{carpeta}/{nombre}", usados);

                    if (a.IdPropuesta is { } idPropuesta)
                    {
                        var pdf = await pdfPropuesta.EjecutarAsync(idPropuesta, ct);
                        if (pdf.IdTipoMensaje == 2 && pdf.Datos is not null) await EscribirAsync(zip, ruta, pdf.Datos, ct);
                        else pendientes.Add($"{carpeta}/{nombre}: {pdf.Mensaje}");
                        continue;
                    }

                    var contenido = a.Ruta is null ? null : await ArchivoExpediente.AbrirAsync(almacen, a.Ruta, ct);
                    if (contenido is null) { pendientes.Add($"{carpeta}/{nombre}: no se encontró en el almacenamiento."); continue; }
                    await using (contenido)
                    {
                        var entrada = zip.CreateEntry(ruta, CompressionLevel.Optimal);
                        await using var destino = entrada.Open();
                        await contenido.CopyToAsync(destino, ct);
                    }
                }

                if (pendientes.Count > 0)
                    await EscribirAsync(zip, $"{numero}/pendientes.txt",
                        Encoding.UTF8.GetBytes("Documentos que no se pudieron incluir:\r\n" + string.Join("\r\n", pendientes)), ct);
            }

            temporal.Position = 0;
            return new(2, "Expediente exportado.", new ArchivoDescargaDto(temporal, $"{numero}.zip", "application/zip"));
        }
        catch
        {
            await temporal.DisposeAsync();
            throw;
        }
    }

    private static async Task EscribirAsync(ZipArchive zip, string ruta, byte[] contenido, CancellationToken ct)
    {
        var entrada = zip.CreateEntry(ruta, CompressionLevel.Optimal);
        await using var destino = entrada.Open();
        await destino.WriteAsync(contenido, ct);
    }

    private static string Limpiar(string texto)
    {
        var limpio = ArchivoExpediente.NombreSeguro(texto);
        return limpio.Length == 0 ? "documento" : limpio;
    }

    private static string Unico(string ruta, HashSet<string> usados)
    {
        var candidata = ruta;
        for (var i = 2; !usados.Add(candidata); i++)
            candidata = $"{Path.ChangeExtension(ruta, null)} ({i}){Path.GetExtension(ruta)}";
        return candidata;
    }
}

// ── HU-31 Documentos ─────────────────────────────────────────────────────────

public class ObtenerDocumentosExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<DocumentosExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<DocumentosExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerDocumentosAsync(idExpediente, idUsuario, ct);
}

/// <summary>Abre un documento del expediente para verlo o descargarlo (el PDF de una propuesta se genera).</summary>
public class ObtenerArchivoExpedienteCasoDeUso(
    IExpedienteRepositorio       repositorio,
    IAlmacenArchivos             almacen,
    GenerarPdfPropuestaCasoDeUso pdfPropuesta)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idExpediente, string clave, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0 || string.IsNullOrWhiteSpace(clave) || clave.Trim().Length > 40) return new(1, "Documento no válido.");

        var u = await repositorio.ObtenerArchivoAsync(idExpediente, clave.Trim().ToLowerInvariant(), idUsuario, ct);
        if (u.IdTipoMensaje != 2 || u.Datos is null) return new(u.IdTipoMensaje, u.Mensaje);

        if (u.Datos.IdPropuesta is { } idPropuesta)
        {
            var pdf = await pdfPropuesta.EjecutarAsync(idPropuesta, ct);
            if (pdf.IdTipoMensaje != 2 || pdf.Datos is null) return new(pdf.IdTipoMensaje, pdf.Mensaje);
            return new(2, u.Mensaje, new ArchivoDescargaDto(new MemoryStream(pdf.Datos), u.Datos.NombreArchivo, "application/pdf"));
        }

        var contenido = u.Datos.Ruta is null ? null : await ArchivoExpediente.AbrirAsync(almacen, u.Datos.Ruta, ct);
        if (contenido is null)
            return new(1, "El documento está registrado pero el archivo no se encontró en el almacenamiento.");

        var tipo = u.Datos.TipoContenido ?? ArchivoExpediente.TipoContenido(Path.GetExtension(u.Datos.NombreArchivo).ToLowerInvariant());
        return new(2, u.Mensaje, new ArchivoDescargaDto(contenido, u.Datos.NombreArchivo, tipo));
    }
}

/// <summary>
/// HU-31 — Adjuntar documento interno: tipo, etapa, nombre, descripción, visibilidad y el archivo (PDF, DOCX, XLSX, PNG o
/// JPG hasta 25 MB). Valida en BD antes de escribir el archivo y lo borra si el registro falla.
/// </summary>
public class AdjuntarDocumentoExpedienteCasoDeUso(IExpedienteRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = ArchivoExpediente.TamanoMaximoDocumento;

    public async Task<RespuestaDto<DocumentoAdjuntadoDto>> EjecutarAsync(
        long idExpediente, AdjuntarDocumentoExpedienteDto datos, Stream? contenido, string? nombreArchivo, long tamano,
        long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        var largo = ArchivoExpediente.Largo(datos.Nombre, 200, "El nombre")
                    ?? ArchivoExpediente.Largo(datos.Descripcion, 1000, "La descripción")
                    ?? ArchivoExpediente.Largo(datos.Etapa, 30, "La etapa");
        if (largo is not null) return new(1, largo);

        var validacion = await repositorio.AdjuntarDocumentoAsync(idExpediente, datos, null, null, null, null, null, true, idUsuario, ct);
        if (validacion.IdTipoMensaje != 2) return validacion;

        if (contenido is null || tamano <= 0) return new(1, "Adjunte el archivo del documento.");
        var (buffer, extension, error) = await ArchivoExpediente.LeerAsync(
            contenido, nombreArchivo, tamano, TamanoMaximoBytes, ArchivoExpediente.ExtensionesDocumento, ct);
        if (error is not null || buffer is null || extension is null) return new(1, error ?? "Archivo no válido.");

        await using (buffer)
        {
            var ruta   = ArchivoExpediente.Ruta(idExpediente, extension);
            var nombre = ArchivoExpediente.NormalizarNombre(nombreArchivo, extension);
            var hash   = ArchivoExpediente.Hash(buffer);
            buffer.Position = 0;
            await almacen.GuardarAsync(ruta, buffer, ct);

            var resultado = await repositorio.AdjuntarDocumentoAsync(idExpediente, datos, ruta, nombre, buffer.Length,
                ArchivoExpediente.TipoContenido(extension), hash, false, idUsuario, ct);
            if (resultado.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
            return resultado;
        }
    }
}

// ── HU-32 Bloqueos y excepciones ─────────────────────────────────────────────

public class RegistrarBloqueoExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<BloqueoRegistradoDto>> EjecutarAsync(long idExpediente, RegistrarBloqueoExpedienteDto datos, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0)
            return Task.FromResult(new RespuestaDto<BloqueoRegistradoDto>(1, "Expediente no válido."));
        var largo = ArchivoExpediente.Largo(datos.Descripcion, 300, "La descripción")
                    ?? ArchivoExpediente.Largo(datos.TipoDocumental, 150, "El tipo documental")
                    ?? ArchivoExpediente.Largo(datos.Impacto, 300, "El impacto")
                    ?? ArchivoExpediente.Largo(datos.Clase, 20, "La clase")
                    ?? ArchivoExpediente.Largo(datos.Tipo, 30, "El tipo");
        if (largo is not null) return Task.FromResult(new RespuestaDto<BloqueoRegistradoDto>(1, largo));
        return repositorio.RegistrarBloqueoAsync(idExpediente, datos, idUsuario, ct);
    }
}

public class PrepararResolucionBloqueoCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionResolucionBloqueoDto>> EjecutarAsync(long idExpediente, long idBloqueador, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0 || idBloqueador <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionResolucionBloqueoDto>(1, "Bloqueo no válido."))
            : repositorio.PrepararResolucionBloqueoAsync(idExpediente, idBloqueador, idUsuario, ct);
}

/// <summary>
/// HU-32 — Resolver un bloqueo (tipo de resolución y evidencia) o cerrar una excepción (resultado, sustento y evidencia).
/// Evidencia: PDF, JPG o PNG hasta 10 MB. Valida en BD antes de escribir el archivo.
/// </summary>
public class ResolverBloqueoExpedienteCasoDeUso(IExpedienteRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = ArchivoExpediente.TamanoMaximoEvidencia;

    public async Task<RespuestaDto<BloqueoResueltoDto>> EjecutarAsync(
        long idExpediente, long idBloqueador, ResolverBloqueoExpedienteDto datos, Stream? contenido, string? nombreArchivo,
        long tamano, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0 || idBloqueador <= 0) return new(1, "Bloqueo no válido.");
        if (ArchivoExpediente.Largo(datos.Sustento, 1000, "El sustento") is { } largo) return new(1, largo);

        var validacion = await repositorio.ResolverBloqueoAsync(idExpediente, idBloqueador, datos, null, null, null, null, null, true, idUsuario, ct);
        if (validacion.IdTipoMensaje != 2) return validacion;

        if (contenido is null || tamano <= 0) return new(1, "Adjunte la evidencia (PDF, JPG o PNG).");
        var (buffer, extension, error) = await ArchivoExpediente.LeerAsync(
            contenido, nombreArchivo, tamano, TamanoMaximoBytes, ArchivoExpediente.ExtensionesEvidencia, ct);
        if (error is not null || buffer is null || extension is null) return new(1, error ?? "Archivo no válido.");

        await using (buffer)
        {
            var ruta   = ArchivoExpediente.Ruta(idExpediente, extension);
            var nombre = ArchivoExpediente.NormalizarNombre(nombreArchivo, extension);
            var hash   = ArchivoExpediente.Hash(buffer);
            buffer.Position = 0;
            await almacen.GuardarAsync(ruta, buffer, ct);

            var resultado = await repositorio.ResolverBloqueoAsync(idExpediente, idBloqueador, datos, ruta, nombre, buffer.Length,
                ArchivoExpediente.TipoContenido(extension), hash, false, idUsuario, ct);
            if (resultado.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
            return resultado;
        }
    }
}

// ── HU-33 Historial y reasignación ───────────────────────────────────────────

public class ObtenerHistorialExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<HistorialExpedienteDto>> EjecutarAsync(long idExpediente, FiltrosHistorialExpedienteDto f, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0)
            return Task.FromResult(new RespuestaDto<HistorialExpedienteDto>(1, "Expediente no válido."));
        if (f.Desde is { } d && f.Hasta is { } h && d.Date > h.Date)
            return Task.FromResult(new RespuestaDto<HistorialExpedienteDto>(1, "La fecha desde no puede ser posterior a la fecha hasta."));
        return repositorio.ObtenerHistorialAsync(idExpediente, Normalizar(f), false, idUsuario, ct);
    }

    internal static FiltrosHistorialExpedienteDto Normalizar(FiltrosHistorialExpedienteDto f) => f with
    {
        TipoEvento = string.IsNullOrWhiteSpace(f.TipoEvento) || f.TipoEvento.Trim().Length > 30 ? null : f.TipoEvento.Trim().ToLowerInvariant(),
        IdUsuario  = f.IdUsuario is > 0 ? f.IdUsuario : null,
        Etapa      = string.IsNullOrWhiteSpace(f.Etapa) || f.Etapa.Trim().Length > 30 ? null : f.Etapa.Trim().ToLowerInvariant(),
        Desde      = f.Desde?.Date,
        Hasta      = f.Hasta?.Date,
    };
}

/// <summary>HU-33 — Exporta el historial filtrado a Excel. La exportación queda registrada en la auditoría.</summary>
public class ExportarHistorialExpedienteCasoDeUso(IExpedienteRepositorio repositorio, IGeneradorExcel excel)
{
    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(long idExpediente, FiltrosHistorialExpedienteDto f, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        if (f.Desde is { } d && f.Hasta is { } h && d.Date > h.Date) return new(1, "La fecha desde no puede ser posterior a la fecha hasta.");

        var r = await repositorio.ObtenerHistorialAsync(idExpediente, ObtenerHistorialExpedienteCasoDeUso.Normalizar(f), true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var contenido = excel.Generar([HojasExpediente.Historial(r.Datos.Eventos)]);
        return new(2, "Historial exportado.", new ArchivoGeneradoDto(contenido, $"Historial-{r.Datos.Numero}.xlsx",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"));
    }
}

public class PrepararReasignacionExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionReasignacionExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionReasignacionExpedienteDto>(1, "Expediente no válido."))
            : repositorio.PrepararReasignacionAsync(idExpediente, idUsuario, ct);
}

public class BuscarResponsablesExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>> EjecutarAsync(long idExpediente, string? busqueda, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>(1, "Expediente no válido."))
            : repositorio.BuscarResponsablesAsync(idExpediente,
                string.IsNullOrWhiteSpace(busqueda) ? null : busqueda.Trim()[..Math.Min(busqueda.Trim().Length, 100)], idUsuario, ct);
}

/// <summary>
/// HU-33 — Reasigna el responsable. El SP registra la auditoría y la notificación en la intranet; aquí se envía además el
/// correo al nuevo responsable (si el correo falla, la reasignación se mantiene y se informa en la respuesta).
/// </summary>
public class ReasignarResponsableExpedienteCasoDeUso(
    IExpedienteRepositorio repositorio,
    NotificadorCorreo      notificador,
    OpcionesCorreo         opciones)
{
    public async Task<RespuestaDto<ReasignacionExpedienteDto>> EjecutarAsync(
        long idExpediente, ReasignarResponsableExpedienteDto datos, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        var largo = ArchivoExpediente.Largo(datos.Comentario, 1000, "El comentario")
                    ?? ArchivoExpediente.Largo(datos.GestionSla, 20, "La gestión del SLA");
        if (largo is not null) return new(1, largo);

        var r = await repositorio.ReasignarResponsableAsync(idExpediente, datos, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null || string.IsNullOrWhiteSpace(r.Datos.CorreoResponsable)) return r;

        var envio = await notificador.EnviarAsync("expediente_reasignado",
            PlantillasCorreo.ExpedienteAsignado(r.Datos, opciones), "expediente", idExpediente, idUsuario, ct);

        var datosFinales = r.Datos with { CorreoEnviado = envio.Enviado, CorreoError = envio.Enviado ? null : envio.Error };
        var mensaje = envio.Enviado ? r.Mensaje : $"{r.Mensaje} No se pudo enviar el correo ({envio.Error}); se notificó en la intranet.";
        return new(2, mensaje, datosFinales);
    }
}

// ── HU-34 Avance de etapa ────────────────────────────────────────────────────

public class PrepararAvanceExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionAvanceExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionAvanceExpedienteDto>(1, "Expediente no válido."))
            : repositorio.PrepararAvanceAsync(idExpediente, idUsuario, ct);
}

public class AvanzarEtapaExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<AvanceExpedienteDto>> EjecutarAsync(long idExpediente, AvanzarEtapaExpedienteDto? datos, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0)
            return Task.FromResult(new RespuestaDto<AvanceExpedienteDto>(1, "Expediente no válido."));
        var comentario = datos?.Comentario?.Trim();
        if (comentario is { Length: > 1000 })
            return Task.FromResult(new RespuestaDto<AvanceExpedienteDto>(1, "El comentario no puede superar los 1000 caracteres."));
        return repositorio.AvanzarEtapaAsync(idExpediente, string.IsNullOrEmpty(comentario) ? null : comentario, idUsuario, ct);
    }
}
