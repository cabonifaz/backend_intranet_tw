using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// HU-55 — Registro del informe de un equipo desde la intranet: contexto de solo lectura, sesión de registro (iniciar, liberar, bloqueo), autorización de cada
/// llamada, marca de trazabilidad (quién registró) y los pasos que no reutilizan un SP móvil (forzar evidencia sin tocar el scorecard del técnico y pausar el otro equipo).
/// Un conflicto de bloqueo llega como IdTipoMensaje 1 con el mensaje prefijado por <c>[409] </c>.
/// </summary>
public interface IRegistroInformeIntranetRepositorio
{
    Task<RespuestaDto<ContextoRegistroIntranetDto>> ObtenerContextoAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct);

    Task<RespuestaDto<ResultadoIniciarRegistroIntranetDto>> IniciarAsync(
        long idRegistrador, long idOs, long idOsEquipo, DateTime inicioUtc, DateTime finUtc, string motivo, string? comentario, CancellationToken ct);

    /// <summary>modo = "lectura" (permiso y resolver el técnico) o "escritura" (además exige la sesión propia vigente y la renueva). idOsEquipo nulo = a nivel de la OS.</summary>
    Task<RespuestaDto<AutorizacionRegistroIntranetDto>> AutorizarAsync(long idRegistrador, long idOs, long? idOsEquipo, string modo, CancellationToken ct);

    Task<RespuestaDto<object>> LiberarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct);

    /// <summary>Estampa id_registrado_por, via = 'intranet' y registrado_en en el informe técnico del equipo.</summary>
    Task<RespuestaDto<object>> MarcarInformeAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct);

    /// <summary>Justo antes de generar: deja el tiempo del equipo en fin − inicio para que la generación no sume el tiempo de la sesión.</summary>
    Task<RespuestaDto<object>> AjustarTiempoAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct);

    Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> ForzarEvidenciaAsync(long idRegistrador, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct);

    Task<RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>> PausarEquipoAbiertoAsync(long idRegistrador, long idOs, long idOsEquipo, string? motivo, CancellationToken ct);
}
