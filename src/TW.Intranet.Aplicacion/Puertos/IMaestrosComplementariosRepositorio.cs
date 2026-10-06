using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Ubigeo, áreas del cliente, códigos de formato y próximo código de ficha (reunión 02-oct).</summary>
public interface IMaestrosComplementariosRepositorio
{
    Task<RespuestaDto<List<UbigeoItemDto>>> ObtenerUbigeoAsync(string nivel, string? departamento, string? provincia, CancellationToken ct);

    Task<RespuestaDto<List<AreaClienteDto>>> ObtenerAreasClienteAsync(long idCliente, CancellationToken ct);

    Task<RespuestaDto<SiguienteCodigoDto>> ObtenerSiguienteCodigoAsync(string entidad, CancellationToken ct);

    Task<RespuestaDto<List<FormatoVentanaDto>>> ObtenerFormatosVentanaAsync(string? clave, CancellationToken ct);
    Task<RespuestaDto<bool>>                    GuardarFormatoVentanaAsync(string clave, GuardarFormatoVentanaDto dto, long idUsuario, CancellationToken ct);
}
