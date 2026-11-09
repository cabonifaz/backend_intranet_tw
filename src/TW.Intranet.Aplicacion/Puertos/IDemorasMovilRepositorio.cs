using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Registro de demoras en ruta de la app móvil (App Mobile HU-05).</summary>
public interface IDemorasMovilRepositorio
{
    Task<RespuestaDto<ContextoDemorasMovilDto>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct);

    /// <summary>La foto ya está guardada en el almacenamiento: aquí solo llega su ruta (o null).</summary>
    Task<RespuestaDto<ResultadoDemoraMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, string tipo, NuevaDemoraMovilDto demora, string? rutaFoto, CancellationToken ct);
}
