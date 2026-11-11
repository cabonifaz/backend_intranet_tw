using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-17 — Firma de informes y constancia de servicio.</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}")]
public class FirmaConstanciaMovilController(
    ObtenerFirmasMovilCasoDeUso            firmas,
    ObtenerResumenFirmasMovilCasoDeUso     resumen,
    FirmarResponsableMovilCasoDeUso        firmarResponsable,
    ObtenerConstanciaMovilCasoDeUso        constancia,
    FirmarConstanciaMovilCasoDeUso         firmarConstancia,
    ObtenerArchivoConstanciaMovilCasoDeUso archivo,
    ILogger<FirmaConstanciaMovilController> logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoPeticion = 8 * 1024 * 1024;

    /// <summary>Formulario multipart del formato físico (foto de la cámara y nombre de quien firmó).</summary>
    public class FormatoFisicoFormulario
    {
        public string?    Nombre { get; set; }
        public IFormFile? Foto   { get; set; }
    }

    /// <summary>Lista de informes de la OS con sus responsables, el plazo de aceptación tácita (segundos que quedan) y el avance de firmas.</summary>
    [HttpGet("firma-informes")]
    public async Task<IActionResult> Lista(long idOs, CancellationToken ct) => Responder(await firmas.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Resumen ligero para el menú de la orden: informes generados y firmados.</summary>
    [HttpGet("firma-informes/resumen")]
    public async Task<IActionResult> Resumen(long idOs, CancellationToken ct) => Responder(await resumen.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Firma de un responsable por dispositivo (trazos) o "cliente ausente". Una firma vale para todos sus informes. Devuelve la lista actualizada.</summary>
    [HttpPost("firma-informes/{clave}/firma")]
    [RequestSizeLimit(40 * 1024)]
    public async Task<IActionResult> Firmar(long idOs, string clave, [FromBody] PeticionFirmaResponsableMovilDto? d, CancellationToken ct) =>
        Responder(await firmarResponsable.EjecutarAsync(IdUsuarioActual, idOs, clave, d, ct));

    /// <summary>Firma de un responsable en formato físico: foto de la cámara de la app y nombre de quien firmó.</summary>
    [HttpPost("firma-informes/{clave}/fisico")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> FirmarFisico(long idOs, string clave, [FromForm] FormatoFisicoFormulario f, CancellationToken ct)
    {
        await using var s = f.Foto?.OpenReadStream();
        return Responder(await firmarResponsable.EjecutarFisicoAsync(IdUsuarioActual, idOs, clave, s, f.Foto?.Length ?? 0, f.Nombre, ct));
    }

    /// <summary>Datos de la constancia: cliente, contacto, equipos intervenidos, firma del cliente, envío y responsables que faltan firmar.</summary>
    [HttpGet("constancia")]
    public async Task<IActionResult> Constancia(long idOs, CancellationToken ct) => Responder(await constancia.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Firma del cliente por dispositivo (trazos) y nombre de quien firma. Devuelve la constancia actualizada.</summary>
    [HttpPost("constancia/firma")]
    [RequestSizeLimit(40 * 1024)]
    public async Task<IActionResult> FirmaCliente(long idOs, [FromBody] PeticionFirmaConstanciaMovilDto? d, CancellationToken ct) =>
        Responder(await firmarConstancia.FirmaAsync(IdUsuarioActual, idOs, d, ct));

    /// <summary>Formato físico de la constancia (opcional): foto de la cámara de la app y nombre de quien firmó.</summary>
    [HttpPost("constancia/fisico")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> FormatoFisico(long idOs, [FromForm] FormatoFisicoFormulario f, CancellationToken ct)
    {
        await using var s = f.Foto?.OpenReadStream();
        return Responder(await firmarConstancia.FisicoAsync(IdUsuarioActual, idOs, s, f.Foto?.Length ?? 0, f.Nombre, ct));
    }

    /// <summary>"Generar constancia": exige la firma del cliente. Si todo está firmado cierra el servicio (PDF y, si está activado, envío por correo).</summary>
    [HttpPost("constancia/generar")]
    public async Task<IActionResult> Generar(long idOs, CancellationToken ct) => Responder(await firmarConstancia.GenerarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>El PDF de la constancia ya generada (o, con ?tipo=foto, la foto del formato físico). Solo de una OS del técnico.</summary>
    [HttpGet("constancia/archivo")]
    public async Task<IActionResult> Archivo(long idOs, [FromQuery] string? tipo, CancellationToken ct)
    {
        var (contenido, mime, mensaje) = await archivo.EjecutarAsync(IdUsuarioActual, idOs, tipo, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Archivo no encontrado.")) : File(contenido, mime!);
    }
}
