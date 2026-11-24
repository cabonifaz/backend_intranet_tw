using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Revisión Técnica — Informe Complementario (23/11/2026). El informe del técnico es inmutable; el supervisor lo corrige con un
// complementario. Cada SP vuelve a validar permiso, alcance y estado; aquí se validan formatos, tamaños y archivos.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

internal static class EntradaInformeComplementario
{
    public const long TamanoMaximoFoto  = 10 * 1024 * 1024;
    public const long TamanoMaximoVideo = 40 * 1024 * 1024;
    public static readonly string[] Momentos = ["antes", "durante", "despues"];

    /// <summary>Tipo real del archivo por sus primeros bytes (no por la extensión): jpg · png · mp4, o null si no es ninguno.</summary>
    public static string? Tipo(ReadOnlySpan<byte> b)
    {
        if (b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return "jpg";
        if (b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) return "png";
        if (b.Length >= 12 && b[4] == (byte)'f' && b[5] == (byte)'t' && b[6] == (byte)'y' && b[7] == (byte)'p') return "mp4";
        return null;
    }

    public static string TipoContenido(string ruta) =>
        ruta.EndsWith(".mp4", StringComparison.OrdinalIgnoreCase) ? "video/mp4"
        : ruta.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ? "image/png"
        : "image/jpeg";

    /// <summary>Valida los ítems de la precotización (mismas reglas que la precotización del informe). Null = válidos.</summary>
    public static string? ValidarPrecotizacion(PrecotizacionComplementarioDto p, int nObservaciones)
    {
        if (p.Items.Count > 50) return "La precotización admite hasta 50 conceptos.";
        if (p.Nota is { Length: > 1000 }) return "La nota admite hasta 1000 caracteres.";
        foreach (var i in p.Items)
        {
            i.Prioridad = string.IsNullOrWhiteSpace(i.Prioridad) ? "media" : i.Prioridad.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(i.Concepto) && i.IdSuministro is null or <= 0) return "Cada concepto debe tener un nombre o elegirse del catálogo.";
            if (i.Cantidad <= 0 || i.Cantidad > 99_999_999m) return "La cantidad de cada concepto debe ser mayor que cero.";
            if (i.Prioridad is not ("alta" or "media" or "opcional")) return "Prioridad no válida: use alta, media u opcional.";
            if (i.IndiceObservacion is { } x && (x < 0 || x >= nObservaciones)) return "La observación vinculada a un concepto no existe en la lista enviada.";
            var e = ValidacionRevisionTecnica.Largo(i.Concepto, 200, "Concepto") ?? ValidacionRevisionTecnica.Largo(i.Codigo, 60, "Código")
                 ?? ValidacionRevisionTecnica.Largo(i.DescripcionTecnica, 500, "Descripción técnica") ?? ValidacionRevisionTecnica.Largo(i.Unidad, 20, "Unidad");
            if (e is not null) return e;
        }
        return null;
    }
}

/// <summary>"Generar Informe Complementario": crea el complementario del informe (o devuelve el que ya existe).</summary>
public class GenerarInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<InformeComplementarioCreadoDto>> EjecutarAsync(long idInforme, long idUsuario, CancellationToken ct = default)
        => idInforme <= 0
            ? Task.FromResult(new RespuestaDto<InformeComplementarioCreadoDto>(1, "Informe no válido."))
            : repositorio.CrearComplementarioAsync(idInforme, idUsuario, ct);
}

/// <summary>Detalle del complementario con los datos del original en solo lectura.</summary>
public class ObtenerInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleInformeComplementarioDto>> EjecutarAsync(long idComplementario, long idUsuario, CancellationToken ct = default)
        => idComplementario <= 0
            ? Task.FromResult(new RespuestaDto<DetalleInformeComplementarioDto>(1, "Informe complementario no válido."))
            : repositorio.ObtenerComplementarioAsync(idComplementario, idUsuario, ct);
}

/// <summary>"Guardar" del complementario: observaciones generales, observaciones, recomendaciones y precotización.</summary>
public class GuardarInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio, INotificadorTiempoReal notificador)
{
    public async Task<RespuestaDto<InformeComplementarioGuardadoDto>> EjecutarAsync(long idComplementario, GuardarInformeComplementarioDto? d, long idUsuario,
                                                                                   CancellationToken ct = default)
    {
        if (idComplementario <= 0 || d is null) return new(1, "Datos no válidos.");
        if (d.ObservacionesGenerales is null && d.Observaciones is null && d.Recomendaciones is null && d.Precotizacion is null)
            return new(1, "No hay cambios que guardar.");
        if (d.ObservacionesGenerales is { Length: > 1000 }) return new(1, "Las observaciones generales admiten hasta 1000 caracteres.");

        // Observaciones y recomendaciones: las mismas reglas del informe
        var error = GuardarInformeTecnicoCasoDeUso.Validar(new GuardarInformeTecnicoDto
        {
            Observaciones   = d.Observaciones,
            Recomendaciones = d.Recomendaciones,
        });
        if (error is null && d.Precotizacion is { } p)
            error = EntradaInformeComplementario.ValidarPrecotizacion(p, d.Observaciones?.Count ?? 0);
        if (error is not null) return new(1, error);

        var r = await repositorio.GuardarComplementarioAsync(idComplementario, d, idUsuario, ct);
        if (r.IdTipoMensaje == 2 && r.Datos is { PrecotizacionNueva: true, IdPrecotizacion: { } idPc } g)
            await notificador.PrecotizacionRecibidaAsync(new PrecotizacionGuardadaDto(idPc, g.NumeroPrecotizacion ?? "", g.ItemsPrecotizacion, "enviado"), idComplementario);
        return r;
    }
}

/// <summary>Sube una foto (JPEG / PNG, hasta 10 MB) o un video (MP4, hasta 40 MB) al complementario.</summary>
public class SubirFotoInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<FotoComplementarioSubidaDto>> EjecutarAsync(long idComplementario, Stream? archivo, long tamano, string? momento,
                                                                             string? descripcion, long? idObservacion, long idUsuario, CancellationToken ct = default)
    {
        if (idComplementario <= 0) return new(1, "Informe complementario no válido.");
        if (archivo is null || tamano <= 0) return new(1, "Falta el archivo.");
        if (tamano > EntradaInformeComplementario.TamanoMaximoVideo) return new(1, "El archivo no puede superar los 40 MB.");
        momento = string.IsNullOrWhiteSpace(momento) ? null : momento.Trim().ToLowerInvariant();
        if (momento is not null && !EntradaInformeComplementario.Momentos.Contains(momento)) return new(1, "Momento no válido: use antes, durante o despues.");
        if (ValidacionRevisionTecnica.Largo(descripcion, 200, "Descripción") is { } e) return new(1, e);

        using var m = new MemoryStream();
        await archivo.CopyToAsync(m, ct);
        var bytes = m.ToArray();
        var tipo = EntradaInformeComplementario.Tipo(bytes);
        if (tipo is null) return new(1, "El archivo debe ser una foto JPEG o PNG, o un video MP4.");
        if (tipo != "mp4" && bytes.LongLength > EntradaInformeComplementario.TamanoMaximoFoto) return new(1, "La foto no puede superar los 10 MB.");

        var ruta = $"informes-complementarios/{idComplementario}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.{tipo}";
        await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);
        RespuestaDto<FotoComplementarioSubidaDto> r;
        try
        {
            r = await repositorio.RegistrarFotoComplementarioAsync(idComplementario, ruta, tipo == "mp4", momento,
                                                                  ValidacionRevisionTecnica.Recortar(descripcion, 200), idObservacion is > 0 ? idObservacion : null, idUsuario, ct);
        }
        catch { await almacen.EliminarAsync(ruta, CancellationToken.None); throw; }
        if (r.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
        return r;
    }
}

/// <summary>Quita una foto o video del complementario (y borra el archivo si lo subió el supervisor y nadie más lo usa).</summary>
public class QuitarFotoInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<object>> EjecutarAsync(long idComplementario, long idEvidencia, long idUsuario, CancellationToken ct = default)
    {
        if (idComplementario <= 0 || idEvidencia <= 0) return new(1, "Foto no encontrada.");
        var r = await repositorio.QuitarFotoComplementarioAsync(idComplementario, idEvidencia, idUsuario, ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);
        if (r.Datos is { } a) await BorrarAsync(almacen, a);
        return new(2, r.Mensaje);
    }

    internal static async Task BorrarAsync(IAlmacenArchivos almacen, ArchivoBorrableDto a)
    {
        await almacen.EliminarAsync(a.Ruta, CancellationToken.None);
        if (!string.IsNullOrEmpty(a.RutaCuadro)) await almacen.EliminarAsync(a.RutaCuadro, CancellationToken.None);
    }
}

/// <summary>Descarta un complementario en borrador (nunca guardado) y borra los archivos que subió el supervisor.</summary>
public class DescartarInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<object>> EjecutarAsync(long idComplementario, long idUsuario, CancellationToken ct = default)
    {
        if (idComplementario <= 0) return new(1, "Informe complementario no válido.");
        var r = await repositorio.DescartarComplementarioAsync(idComplementario, idUsuario, ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);
        foreach (var a in r.Datos ?? []) await QuitarFotoInformeComplementarioCasoDeUso.BorrarAsync(almacen, a);
        return new(2, r.Mensaje);
    }
}

/// <summary>El archivo (foto, video o, con cuadro, su miniatura) de una evidencia del complementario.</summary>
public class ObtenerArchivoFotoInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? TipoContenido, string? Mensaje)> EjecutarAsync(long idComplementario, long idEvidencia, bool cuadro, long idUsuario,
                                                                                              CancellationToken ct = default)
    {
        if (idComplementario <= 0 || idEvidencia <= 0) return (null, null, "Foto no encontrada.");
        var r = await repositorio.ObtenerArchivoFotoComplementarioAsync(idComplementario, idEvidencia, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return (null, null, r.Mensaje);
        var ruta = cuadro && r.Datos.RutaCuadro is not null ? r.Datos.RutaCuadro : r.Datos.Ruta;
        var s = await almacen.AbrirLecturaAsync(ruta, ct);
        return s is null ? (null, null, "El archivo ya no está disponible.") : (s, EntradaInformeComplementario.TipoContenido(ruta), null);
    }
}

/// <summary>PDF del complementario (se genera en el momento con los datos vigentes).</summary>
public class GenerarPdfInformeComplementarioCasoDeUso(IRevisionTecnicaRepositorio repositorio, IAlmacenArchivos almacen, IGeneradorInformeComplementarioPdf pdf)
{
    private const int MaxImagenes = 24;

    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(long idComplementario, long idUsuario, CancellationToken ct = default)
    {
        if (idComplementario <= 0) return new(1, "Informe complementario no válido.");
        var r = await repositorio.ObtenerComplementarioAsync(idComplementario, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        // Imágenes de las fotos (los videos van con su miniatura si la tienen; si no, solo se listan)
        var imagenes = new Dictionary<long, byte[]>();
        foreach (var f in r.Datos.Fotos.Take(MaxImagenes))
        {
            var archivo = await repositorio.ObtenerArchivoFotoComplementarioAsync(idComplementario, f.IdEvidencia, idUsuario, ct);
            if (archivo.IdTipoMensaje != 2 || archivo.Datos is null) continue;
            var ruta = f.EsVideo ? archivo.Datos.RutaCuadro : archivo.Datos.Ruta;
            if (string.IsNullOrEmpty(ruta) || ruta.EndsWith(".mp4", StringComparison.OrdinalIgnoreCase)) continue;
            await using var s = await almacen.AbrirLecturaAsync(ruta, ct);
            if (s is null) continue;
            using var m = new MemoryStream();
            await s.CopyToAsync(m, ct);
            if (EntradaInformeComplementario.Tipo(m.GetBuffer().AsSpan(0, (int)Math.Min(m.Length, 16))) is "jpg" or "png") imagenes[f.IdEvidencia] = m.ToArray();
        }

        var lima = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, ZonaLima());
        var bytes = pdf.Generar(new DatosInformeComplementarioPdf(r.Datos, imagenes, lima));
        var numero = r.Datos.Cabecera.NumeroComplementario ?? $"CMP-{idComplementario}";
        return new(2, "PDF generado.", new ArchivoGeneradoDto(bytes, $"informe-complementario-{numero}.pdf", "application/pdf"));
    }

    private static TimeZoneInfo ZonaLima()
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById("America/Lima"); }
        catch { return TimeZoneInfo.CreateCustomTimeZone("Lima", TimeSpan.FromHours(-5), "Lima", "Lima"); }
    }
}
