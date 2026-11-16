using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Ingreso de equipos de la OS desde la app móvil (App Mobile HU-22).</summary>
public interface IIngresoEquiposMovilRepositorio
{
    Task<RespuestaDto<IngresosOsMovilDto>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct);

    Task<RespuestaDto<EquipoAgregadoMovilDto>> AgregarExistenteAsync(long idUsuario, long idOs, string codigo, bool soloVerificar, CancellationToken ct);

    Task<RespuestaDto<ResultadoIngresoEquipoMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, long idOsEquipo, string estado, string? observacion, IReadOnlyList<string> rutasFotos, CancellationToken ct);
}
