using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IProcedimientosRepositorio
{
    Task<RespuestaDto<ProcedimientosPaginadoDto>> ObtenerProcedimientosAsync(
        string? busqueda, int? anio, string? estado, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<ProcedimientoDetalleDto>> ObtenerProcedimientoPorIdAsync(
        long idProcedimiento, CancellationToken ct);

    Task<RespuestaDto<List<OpcionCatalogoDto>>> ObtenerOpcionesAsync(CancellationToken ct);

    Task<RespuestaDto<long>> GuardarProcedimientoAsync(
        GuardarProcedimientoDto dto, long idUsuario, string? pcRegistro, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoProcedimientoAsync(
        long idProcedimiento, string estado, long idUsuario, CancellationToken ct);

    // ── Carga real del PDF aprobado ──────────────────────────────────────────
    /// <summary>Permiso del usuario para cargar el PDF. idProcedimiento = 0 evalúa solo el permiso.</summary>
    Task<RespuestaDto<PermisoPdfProcedimientoDto>> ValidarCargaPdfAsync(
        long idProcedimiento, long idUsuario, CancellationToken ct);

    /// <summary>Registra en BD un PDF ya guardado en el almacenamiento.</summary>
    Task<RespuestaDto<PdfProcedimientoDto>> RegistrarPdfAsync(
        long idProcedimiento, string ruta, string nombreOriginal, long tamanoBytes, string hashSha256,
        long idUsuario, string? pcRegistro, CancellationToken ct);

    /// <summary>Ruta interna y nombre del PDF cargado.</summary>
    Task<RespuestaDto<RutaPdfProcedimientoDto>> ObtenerRutaPdfAsync(long idProcedimiento, CancellationToken ct);
}
