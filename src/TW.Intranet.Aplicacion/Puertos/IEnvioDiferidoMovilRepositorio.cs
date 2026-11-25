using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>App móvil sin señal — constancia de los registros enviados tarde (SP_RegistrarEnvioDiferidoMovil y SP_ListarEnviosDiferidosMovil).</summary>
public interface IEnvioDiferidoMovilRepositorio
{
    Task<RespuestaDto<object>> RegistrarAsync(
        long idUsuario, string metodo, string ruta, long? idOs, long? idOsEquipo, DateTime capturadoUtc, string? motivo, int intentos, CancellationToken ct);

    Task<RespuestaDto<IReadOnlyList<EnvioDiferidoDto>>> ListarAsync(long idOs, long? idOsEquipo, CancellationToken ct);
}
