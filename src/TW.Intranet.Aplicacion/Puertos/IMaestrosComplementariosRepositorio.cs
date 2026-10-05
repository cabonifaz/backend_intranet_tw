using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Ubigeo, áreas del cliente y códigos de formato por ventana (reunión 02-oct).</summary>
public interface IMaestrosComplementariosRepositorio
{
    Task<RespuestaDto<List<UbigeoItemDto>>> ObtenerUbigeoAsync(string nivel, string? departamento, string? provincia, CancellationToken ct);

    Task<RespuestaDto<List<AreaClienteDto>>> ObtenerAreasClienteAsync(long idCliente, bool soloActivas, CancellationToken ct);
    Task<RespuestaDto<AreaClienteDto>>       GuardarAreaClienteAsync(long idCliente, GuardarAreaClienteDto dto, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<bool>>                 CambiarEstadoAreaClienteAsync(long idArea, string estado, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<List<FormatoVentanaDto>>> ObtenerFormatosVentanaAsync(string? clave, CancellationToken ct);
    Task<RespuestaDto<bool>>                    GuardarFormatoVentanaAsync(string clave, GuardarFormatoVentanaDto dto, long idUsuario, CancellationToken ct);
}
