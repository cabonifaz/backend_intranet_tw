using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Correlativos de Metrología en la app móvil (App Mobile HU-14 técnico / HU-34 Jefe de Metrología). Todo sale de procedimientos almacenados.</summary>
public interface ICorrelativosMovilRepositorio
{
    // Técnico
    Task<RespuestaDto<SolicitudCorrelativoDto>> ObtenerSolicitudAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);
    Task<RespuestaDto<TicketCreadoDto>> SolicitarAsync(long idUsuario, long idOs, long idOsEquipo, int idTipo, string? observacion, CancellationToken ct);
    Task<RespuestaDto<IReadOnlyList<TicketCorrelativoDto>>> ObtenerTicketsAsync(long idUsuario, string filtro, long? idOs, CancellationToken ct);
    Task<RespuestaDto<CertificadoGuardadoDto>> GuardarCertificadoAsync(long idUsuario, long idOs, long idOsEquipo, string certificado, CancellationToken ct);
    Task<RespuestaDto<ReservaGeneradaDto>> GenerarReservaAsync(long idUsuario, string modo, CancellationToken ct);

    // Jefe de Metrología
    Task<RespuestaDto<CorrelativosJefaturaDto>> ObtenerPanelJefaturaAsync(long idUsuario, CancellationToken ct);
    Task<RespuestaDto<AsignacionCorrelativoDto>> AsignarAsync(long idUsuario, long idTicket, string? correlativo, CancellationToken ct);
}
