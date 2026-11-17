using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Biblioteca de procedimientos de la app móvil (App Mobile HU-24).</summary>
public interface IProcedimientosMovilRepositorio
{
    Task<RespuestaDto<BibliotecaProcedimientosMovilDto>> ObtenerBibliotecaAsync(long idUsuario, CancellationToken ct);
}
