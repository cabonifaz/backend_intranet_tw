using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IUsuariosRepositorio
{
    // ── Usuarios ──────────────────────────────────────────────────────────────
    Task<RespuestaDto<UsuariosPaginadoDto>> ObtenerUsuariosAsync(
        string? busqueda, string? rol, string? estado, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<UsuarioDetalleDto>> ObtenerUsuarioPorIdAsync(
        long idUsuario, CancellationToken ct);

    Task<RespuestaDto<List<UsuarioListaItemDto>>> ObtenerJefesDisponiblesAsync(CancellationToken ct);

    Task<RespuestaDto<List<SedeOperativaDto>>> ObtenerSedesOperativasAsync(CancellationToken ct);

    Task<RespuestaDto<long>> GuardarUsuarioAsync(
        GuardarUsuarioDto dto, string? passwordHash, DateTime? fechaExpiracion,
        long idEjecutor, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoUsuarioAsync(
        long idUsuario, string estado, long idEjecutor, CancellationToken ct);

    // ── Suplentes ─────────────────────────────────────────────────────────────
    Task<RespuestaDto<SuplentesPaginadoDto>> ObtenerSuplentesAsync(
        string? busqueda, string? estado, int pagina, int porPagina, CancellationToken ct);

    Task<RespuestaDto<SuplenteListaItemDto>> ObtenerSuplentePorIdAsync(
        long idAsignacion, CancellationToken ct);

    /// <param name="perspectiva">"titular" o "suplente".</param>
    Task<RespuestaDto<List<SuplenteListaItemDto>>> ObtenerSuplenciasPorUsuarioAsync(
        long idUsuario, string perspectiva, CancellationToken ct);

    Task<RespuestaDto<long>> GuardarSuplenteAsync(
        GuardarSuplenteDto dto, DateTime fechaInicio, DateTime? fechaFin,
        string usuario, CancellationToken ct);

    Task<RespuestaDto<object>> CambiarEstadoSuplenteAsync(
        long idAsignacion, string estado, string usuario, CancellationToken ct);
}
