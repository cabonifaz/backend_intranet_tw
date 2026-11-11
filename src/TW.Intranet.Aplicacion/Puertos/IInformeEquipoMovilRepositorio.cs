using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Cabecera del informe y Hard Stop de cierre del trabajo en el equipo (App Mobile HU-15 / HU-16).</summary>
public interface IInformeEquipoMovilRepositorio
{
    Task<RespuestaDto<CabeceraInformeMovilDto>> ObtenerCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);

    /// <summary>json: las secciones de la cabecera que se guardan, ya validadas por el caso de uso (el SP vuelve a validar y calcula E, EMP y conformidad).</summary>
    Task<RespuestaDto<ResultadoGuardarCabeceraMovilDto>> GuardarCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, string json, CancellationToken ct);

    Task<RespuestaDto<FotoFallaMovilDto>> RegistrarFotoFallaAsync(
        long idUsuario, long idOs, long idOsEquipo, string rutaArchivo, decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, CancellationToken ct);

    Task<RespuestaDto<CierreEquipoMovilDto>> ValidarCierreAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);

    Task<RespuestaDto<InformeGeneradoMovilDto>> GenerarInformeAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);
}
