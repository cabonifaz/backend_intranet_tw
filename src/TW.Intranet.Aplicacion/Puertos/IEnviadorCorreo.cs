using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// Servicio externo de envío de correo (hoy Brevo por API HTTPS).
/// Nunca lanza excepciones: cualquier error se devuelve en el resultado.
/// </summary>
public interface IEnviadorCorreo
{
    /// <summary>Código del proveedor que se guarda en correo_envio, ej. "brevo".</summary>
    string Proveedor { get; }

    Task<ResultadoEnvioCorreoDto> EnviarAsync(MensajeCorreoDto mensaje, CancellationToken ct);
}
