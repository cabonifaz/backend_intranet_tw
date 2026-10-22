using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Agenda de servicios del técnico en la app móvil (App Mobile HU-03).</summary>
public interface IServiciosMovilRepositorio
{
    Task<RespuestaDto<List<ServicioProgramadoMovilDto>>> ObtenerProgramadosAsync(
        long idUsuario, string filtro, string? busqueda, CancellationToken ct);
}
