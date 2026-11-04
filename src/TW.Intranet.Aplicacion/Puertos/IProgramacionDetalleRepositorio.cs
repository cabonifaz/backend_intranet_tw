using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-37 Detalle de la Programación y registro de la confirmación con el cliente (Sprint 5).</summary>
public interface IProgramacionDetalleRepositorio
{
    Task<RespuestaDto<DetalleProgramacionDto>> ObtenerDetalleAsync(long idProgramacion, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<RespuestaClienteRegistradaDto>> RegistrarRespuestaClienteAsync(
        NuevaRespuestaCliente respuesta, long idUsuario, CancellationToken ct);
}
