using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-53 Registro operativo del Asistente de Seguimiento (Sprint 5).</summary>
public interface IRegistroAsistenteRepositorio
{
    Task<RespuestaDto<FormularioRegistroAsistenteDto>> ObtenerFormularioAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<RegistroAsistenteCreadoDto>>     RegistrarAsync(long idUsuario, long idOs, RegistroAsistenteNormalizado datos, CancellationToken ct);
}
