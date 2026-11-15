using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-52 / HU-57 (Sprint 5) Aprobaciones y viáticos de una OS ─────────────────────────────────────────────

/// <summary>
/// Validación de entrada. Desarrollo seguro: identificadores positivos, tipo y acción de listas cerradas, comentario de 1 a 500 caracteres,
/// n del comprobante entre 1 y 5. Los SPs vuelven a validar el permiso, el área del encargado y que lo pedido sea de ESA OS (anti-IDOR).
/// </summary>
internal static class EntradaAprobacionesViaticos
{
    internal static readonly string[] Tipos = ["salida", "llegada", "evidencia", "ensayo"];
    internal const int MaxComentario = 500;

    internal static string? ErrorIdOs(long idOs) => idOs <= 0 ? "El servicio indicado no es válido." : null;

    internal static (string? Tipo, string? Comentario, string? Error) NormalizarResolucion(long idOs, string? tipo, long id, ResolverAprobacionServicioDto? dto)
    {
        if (ErrorIdOs(idOs) is { } e) return (null, null, e);
        var t = (tipo ?? "").Trim().ToLowerInvariant();
        if (!Tipos.Contains(t)) return (null, null, "Tipo de aprobación no válido. Use salida, llegada, evidencia o ensayo.");
        if (id <= 0) return (null, null, "La aprobación indicada no es válida.");
        if (dto?.Aprobar is null) return (null, null, "Indica si apruebas o rechazas.");
        var c = dto.Comentario?.Trim() ?? "";
        if (c.Length == 0) return (null, null, "Escribe un comentario.");
        if (c.Length > MaxComentario) return (null, null, $"El comentario admite hasta {MaxComentario} caracteres.");
        if (c.Any(ch => char.IsControl(ch) && ch is not ('\n' or '\r' or '\t'))) return (null, null, "El comentario tiene caracteres no permitidos.");
        return (t, c, null);
    }

    /// <summary>Tipo de contenido permitido para un comprobante (imagen o PDF), por la extensión de la ruta guardada.</summary>
    internal static string? TipoComprobante(string ruta) => Path.GetExtension(ruta).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" => "image/jpeg",
        ".png"            => "image/png",
        ".webp"           => "image/webp",
        ".pdf"            => "application/pdf",
        _                 => null
    };
}

/// <summary>Pestaña Aprobaciones del Detalle del Servicio en Ruta (HU-52): salida, llegada forzada, evidencias forzadas y ensayos con error.</summary>
public class ObtenerAprobacionesServicioRutaCasoDeUso(IAprobacionesViaticosServicioRepositorio repositorio)
{
    public Task<RespuestaDto<AprobacionesServicioDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaAprobacionesViaticos.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<AprobacionesServicioDto>(1, e))
            : repositorio.ObtenerAprobacionesAsync(idUsuario, idOs, ct);
}

/// <summary>Aprobar o rechazar una aprobación de la OS. El SP decide si el usuario puede (encargado del área, supervisión general o administrador).</summary>
public class ResolverAprobacionServicioRutaCasoDeUso(IAprobacionesViaticosServicioRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, long idOs, string? tipo, long id, ResolverAprobacionServicioDto? dto, CancellationToken ct = default)
    {
        var (t, comentario, error) = EntradaAprobacionesViaticos.NormalizarResolucion(idOs, tipo, id, dto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<bool>(1, error))
            : repositorio.ResolverAprobacionAsync(idUsuario, idOs, t!, id, dto!.Aprobar!.Value, comentario!, ct);
    }
}

/// <summary>Pestaña Viáticos del Detalle del Servicio en Ruta (HU-52): lo asignado y lo rendido en vivo. El Asistente ve sin permisos prog_*.</summary>
public class ObtenerViaticosServicioRutaCasoDeUso(IAprobacionesViaticosServicioRepositorio repositorio)
{
    public Task<RespuestaDto<ViaticosOsDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
        => EntradaAprobacionesViaticos.ErrorIdOs(idOs) is { } e
            ? Task.FromResult(new RespuestaDto<ViaticosOsDto>(1, e))
            : repositorio.ObtenerViaticosServicioAsync(idUsuario, idOs, ct);
}

/// <summary>Revisar (aprobar, observar o rechazar) un gasto rendido desde el Seguimiento. El SP comprueba que el gasto sea de ESA OS.</summary>
public class RevisarGastoServicioRutaCasoDeUso(IAprobacionesViaticosServicioRepositorio repositorio)
{
    public Task<RespuestaDto<RevisarGastoResultadoDto>> EjecutarAsync(long idUsuario, long idOs, long idGasto, RevisarGastoDto? dto, CancellationToken ct = default)
    {
        if (EntradaAprobacionesViaticos.ErrorIdOs(idOs) is { } e)
            return Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, e));
        // Mismas reglas que la revisión desde la Programación (HU-45): acción de lista cerrada y comentario según la acción
        var (accion, comentario, error) = EntradaViaticos.NormalizarRevision(idOs, idGasto, dto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, error))
            : repositorio.RevisarGastoServicioAsync(idUsuario, idOs, idGasto, accion!, comentario, ct);
    }
}

/// <summary>
/// Comprobante n (1 a 5) de un gasto, servido con autenticación. Solo rutas del almacenamiento del sistema (sin "..") con extensión de imagen o PDF;
/// un enlace externo no se sirve desde aquí.
/// </summary>
public class ObtenerComprobanteGastoServicioRutaCasoDeUso(IAprobacionesViaticosServicioRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idUsuario, long idOs, long idGasto, int n, CancellationToken ct = default)
    {
        if (EntradaAprobacionesViaticos.ErrorIdOs(idOs) is { } e)
            return new(1, e);
        if (idGasto <= 0)
            return new(1, "El gasto indicado no es válido.");
        if (n is < 1 or > 5)
            return new(1, "El comprobante indicado no es válido (1 a 5).");

        var r = await repositorio.ObtenerRutaComprobanteAsync(idUsuario, idOs, idGasto, n, ct);
        if (r.IdTipoMensaje != 2 || string.IsNullOrWhiteSpace(r.Datos))
            return new(r.IdTipoMensaje == 2 ? 1 : r.IdTipoMensaje, r.IdTipoMensaje == 2 ? "El gasto no tiene ese comprobante." : r.Mensaje);

        var ruta = r.Datos.Trim();
        if (ruta.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || ruta.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return new(1, "El comprobante de este gasto es un enlace externo.");
        ruta = ruta.TrimStart('/');
        var tipo = EntradaAprobacionesViaticos.TipoComprobante(ruta);
        if (tipo is null || ruta.Contains(".."))
            return new(1, "El comprobante de este gasto no es una imagen ni un PDF.");

        var stream = await almacen.AbrirLecturaAsync(ruta, ct);
        return stream is null
            ? new(1, "No se encontró el archivo del comprobante.")
            : new(2, "Éxito.", new ArchivoDescargaDto(stream, Path.GetFileName(ruta), tipo));
    }
}

/// <summary>Viáticos de la OS de un informe técnico (HU-57), con el cierre de la rendición. Siempre solo lectura.</summary>
public class ObtenerViaticosInformeCasoDeUso(IAprobacionesViaticosServicioRepositorio repositorio)
{
    public Task<RespuestaDto<ViaticosOsDto>> EjecutarAsync(long idUsuario, long idInforme, CancellationToken ct = default)
        => idInforme <= 0
            ? Task.FromResult(new RespuestaDto<ViaticosOsDto>(1, "El informe no existe o no está en tu alcance."))
            : repositorio.ObtenerViaticosInformeAsync(idUsuario, idInforme, ct);
}
