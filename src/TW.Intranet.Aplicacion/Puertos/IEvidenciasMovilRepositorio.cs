using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Registro fotográfico del equipo en la app móvil (App Mobile HU-11 / HU-12 / HU-13).</summary>
public interface IEvidenciasMovilRepositorio
{
    /// <summary>previo = true: descarga por adelantado con señal (HU-18), sin los Hard Stop de la llegada ni de "equipo iniciado"; solo lectura.</summary>
    Task<RespuestaDto<EvidenciasMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct, bool previo = false);

    Task<RespuestaDto<ResultadoEvidenciaMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, long idOsEquipo, string codigo, int pagina, string? rutaArchivo, string? rutaCuadro, decimal? duracionSeg,
        decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, string? qrTexto, ResultadoValidacionEvidenciaIa ia, CancellationToken ct);

    Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> ForzarAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct);

    /// <summary>Quita (borrado lógico) una foto adicional del técnico mientras el equipo está en ejecución.</summary>
    Task<RespuestaDto<object>> QuitarAdicionalAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct);

    Task<RespuestaDto<ArchivoEvidenciaMovilDto>> ObtenerArchivoAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct);
}

/// <summary>Validación con IA de una captura del registro fotográfico (Gemini; sin API key responde "omitida" y no bloquea).</summary>
public interface IValidadorEvidenciaIa
{
    Task<ResultadoValidacionEvidenciaIa> ValidarAsync(SolicitudValidacionEvidenciaIa solicitud, CancellationToken ct);
}
