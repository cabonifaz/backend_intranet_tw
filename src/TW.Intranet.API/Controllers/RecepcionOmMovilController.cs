using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-23 — Recepción de instrumentos (OM) en el taller (Técnico de Metrología): lista «Por recibir» / «Recibidos hoy», detalle de la OM con sus instrumentos, fotos de recepción
/// (solo cámara, sin IA), lectura de la etiqueta del instrumento, registro de la recepción (total o parcial, con la firma de quien entrega) y la constancia en PDF.
/// La OM vive en orden_servicio con tipo OM; el técnico siempre sale del token y solo ve las OM que tiene asignadas. Todo exige conexión.
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/recepcion-om")]
public class RecepcionOmMovilController(
    ObtenerListaRecepcionOmMovilCasoDeUso      lista,
    ObtenerDetalleRecepcionOmMovilCasoDeUso    detalle,
    SubirFotoRecepcionOmMovilCasoDeUso         subirFoto,
    QuitarFotoRecepcionOmMovilCasoDeUso        quitarFoto,
    ObtenerFotosRecepcionOmMovilCasoDeUso      fotos,
    ObtenerArchivoFotoRecepcionOmMovilCasoDeUso archivoFoto,
    BuscarQrRecepcionOmMovilCasoDeUso          buscarQr,
    RegistrarRecepcionOmMovilCasoDeUso         registrar,
    ObtenerConstanciaRecepcionOmMovilCasoDeUso constancia,
    ILogger<RecepcionOmMovilController>        logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoFoto = 7 * 1024 * 1024;

    /// <summary>Formulario multipart de una foto de recepción: JPEG de la cámara (y, opcional, la hora ISO UTC en que se tomó; hoy solo informativa).</summary>
    public class FotoRecepcionFormulario
    {
        public IFormFile? Archivo { get; set; }
        public string? CapturadoEn { get; set; }
    }

    /// <summary>«Por recibir» y «Recibidos hoy» de las OM del técnico. ?busqueda= filtra por N° de OM, cliente o N° de guía (hasta 80 caracteres).</summary>
    [HttpGet]
    public async Task<IActionResult> Lista([FromQuery] string? busqueda, CancellationToken ct)
        => Responder(await lista.EjecutarAsync(IdUsuarioActual, busqueda, ct));

    /// <summary>Resumen de la OM, sus instrumentos (recibidos o pendientes) y las recepciones ya registradas. Solo de una OM del técnico.</summary>
    [HttpGet("{idOs:long}")]
    public async Task<IActionResult> Detalle(long idOs, CancellationToken ct)
        => Responder(await detalle.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>Foto de recepción de un instrumento pendiente (JPEG de la cámara, hasta 6 MB, máximo 8 pendientes por instrumento). Devuelve su id para enviarlo al registrar la recepción.</summary>
    [HttpPost("{idOs:long}/instrumentos/{idOsEquipo:long}/fotos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoFoto)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoFoto)]
    public async Task<IActionResult> SubirFoto(long idOs, long idOsEquipo, [FromForm] FotoRecepcionFormulario f, CancellationToken ct)
    {
        await using var a = f.Archivo?.OpenReadStream();
        return Responder(await subirFoto.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, a, f.Archivo?.Length ?? 0, ct));
    }

    /// <summary>Fotos pendientes (sin registrar) del técnico para un instrumento: para reanudar si cerró la pantalla a medias.</summary>
    [HttpGet("{idOs:long}/instrumentos/{idOsEquipo:long}/fotos")]
    public async Task<IActionResult> Fotos(long idOs, long idOsEquipo, CancellationToken ct)
        => Responder(await fotos.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, ct));

    /// <summary>Quita una foto pendiente (aún no ligada a una recepción registrada) del propio técnico.</summary>
    [HttpDelete("{idOs:long}/instrumentos/{idOsEquipo:long}/fotos/{idFoto:long}")]
    public async Task<IActionResult> QuitarFoto(long idOs, long idOsEquipo, long idFoto, CancellationToken ct)
        => Responder(await quitarFoto.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, idFoto, ct));

    /// <summary>El JPEG de una foto de recepción (solo del técnico, o de una recepción de una OM suya).</summary>
    [HttpGet("fotos/{idFoto:long}/archivo")]
    public async Task<IActionResult> ArchivoFoto(long idFoto, CancellationToken ct)
    {
        var (contenido, tipo, mensaje) = await archivoFoto.EjecutarAsync(IdUsuarioActual, idFoto, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Foto no encontrada.")) : File(contenido, tipo!, enableRangeProcessing: true);
    }

    /// <summary>Resuelve el texto leído de una etiqueta QR / serie / código al instrumento de ESTA OM (?texto=). 400 si no corresponde o ya se recibió.</summary>
    [HttpGet("{idOs:long}/buscar-qr")]
    public async Task<IActionResult> BuscarQr(long idOs, [FromQuery] string? texto, CancellationToken ct)
        => Responder(await buscarQr.EjecutarAsync(IdUsuarioActual, idOs, texto, ct));

    /// <summary>
    /// Registra la recepción de uno o varios instrumentos de la OM (guía, medio de entrega, quién entrega, estado físico y observaciones de cada instrumento, accesorios, 3 a 8 fotos y la firma de
    /// quien entrega). Si quedan instrumentos sin recibir es PARCIAL: exige el motivo y avisa a Programación. Genera la constancia en PDF y, si está activo, la envía al contacto del cliente.
    /// </summary>
    [HttpPost("{idOs:long}")]
    [RequestSizeLimit(64 * 1024)]
    public async Task<IActionResult> Registrar(long idOs, [FromBody] PeticionRecepcionOmMovilDto? d, CancellationToken ct)
        => Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, d, ct));

    /// <summary>Constancia de recepción en PDF (la guardada o, si ya no está, una nueva con los mismos datos). 400 JSON si no existe o no es de una OM del técnico.</summary>
    [HttpGet("recepciones/{idRecepcion:long}/constancia")]
    public async Task<IActionResult> Constancia(long idRecepcion, CancellationToken ct)
    {
        var r = await constancia.EjecutarAsync(IdUsuarioActual, idRecepcion, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return r.IdTipoMensaje == 1 ? BadRequest(new RespuestaDto<object>(1, r.Mensaje)) : StatusCode(500, new RespuestaDto<object>(3, SeguridadAppMovil.MensajeErrorGenerico));
        return File(r.Datos, "application/pdf", $"constancia-recepcion-{idRecepcion}.pdf");
    }
}
