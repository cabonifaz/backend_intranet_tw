using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Servicio Técnico › Revisión de Informes › Informe Complementario (cambio del 23/11/2026, HU-56 a HU-60). El informe que genera el técnico
/// desde la app es inmutable: si hace falta, el Supervisor Técnico genera un INFORME COMPLEMENTARIO (uno por informe) que trae precargadas
/// las observaciones, recomendaciones y fotos del original, donde agrega o edita fotos, videos, observaciones y recomendaciones y registra
/// la precotización (opcional). Se edita mientras el original no esté revisado; al revisarlo, los dos quedan cerrados.
/// Permisos: rt_editar (generar, guardar, fotos, descartar) · rt_bandeja o precot_ver (ver, fotos y PDF). Cada SP vuelve a validar
/// el permiso, el alcance (informes de los técnicos de su área; Comercial, la precotización en su alcance) y el estado.
/// </summary>
[ApiController]
[Route("api/servicio-tecnico/informes")]
[Authorize]
public class InformeComplementarioController(
    GenerarInformeComplementarioCasoDeUso            generar,
    ObtenerInformeComplementarioCasoDeUso            obtener,
    GuardarInformeComplementarioCasoDeUso            guardar,
    DescartarInformeComplementarioCasoDeUso          descartar,
    SubirFotoInformeComplementarioCasoDeUso          subirFoto,
    QuitarFotoInformeComplementarioCasoDeUso         quitarFoto,
    ActualizarDescripcionFotoInformeComplementarioCasoDeUso descripcionFoto,
    ObtenerArchivoFotoInformeComplementarioCasoDeUso archivoFoto,
    GenerarPdfInformeComplementarioCasoDeUso         pdf,
    ILogger<InformeComplementarioController>         logger) : ControllerBase
{
    /// <summary>Tamaño máximo del multipart de una foto / video (40 MB del video + el resto del formulario).</summary>
    private const long TamanoMaximoSubida = 41 * 1024 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    /// <summary>2 → 200, 1 → 400. Un error del sistema (3) no expone el detalle de la base de datos: va al log.</summary>
    private IActionResult Responder<T>(RespuestaDto<T> r)
    {
        if (r.IdTipoMensaje == 3)
        {
            logger.LogError("Informe complementario: error en {Ruta} (usuario {IdUsuario}): {Detalle}", Request.Path.Value, IdUsuarioActual, r.Mensaje);
            return StatusCode(500, new RespuestaDto<T>(3, "No se pudo completar la operación. Inténtalo de nuevo."));
        }
        return r.IdTipoMensaje == 2 ? Ok(r) : BadRequest(r);
    }

    /// <summary>Formulario multipart de una foto o video del complementario.</summary>
    public class FotoComplementarioFormulario
    {
        /// <summary>JPEG / PNG (hasta 10 MB) o MP4 (hasta 40 MB).</summary>
        public IFormFile? Archivo       { get; set; }
        /// <summary>antes · durante (defecto) · despues.</summary>
        public string?    Momento       { get; set; }
        /// <summary>Opcional, hasta 200 caracteres.</summary>
        public string?    Descripcion   { get; set; }
        /// <summary>Observación del complementario a la que se vincula (opcional).</summary>
        public long?      IdObservacion { get; set; }
    }

    /// <summary>"Generar Informe Complementario" del informe {idInforme}. Precarga observaciones, recomendaciones y fotos del original.
    /// Uno solo por informe: si ya existe devuelve el mismo (creado = false).</summary>
    [RequierePermiso("rt_editar")]
    [HttpPost("{idInforme:long}/complementario")]
    public async Task<IActionResult> Generar(long idInforme, CancellationToken ct = default)
        => Responder(await generar.EjecutarAsync(idInforme, IdUsuarioActual, ct));

    /// <summary>Detalle del complementario: sus datos, observaciones, recomendaciones, fotos y precotización, y los datos generales,
    /// procedimiento y ensayos del informe original (solo lectura).</summary>
    [RequierePermiso("rt_bandeja", "precot_ver")]
    [HttpGet("complementarios/{idComplementario:long}")]
    public async Task<IActionResult> Detalle(long idComplementario, CancellationToken ct = default)
        => Responder(await obtener.EjecutarAsync(idComplementario, IdUsuarioActual, ct));

    /// <summary>"Guardar": observaciones generales, observaciones, recomendaciones y precotización (secciones opcionales; una lista enviada
    /// reemplaza a la anterior). Se rechaza si el complementario queda sin nada propio frente al original.</summary>
    [RequierePermiso("rt_editar")]
    [RequestSizeLimit(512 * 1024)]
    [HttpPut("complementarios/{idComplementario:long}")]
    public async Task<IActionResult> Guardar(long idComplementario, [FromBody] GuardarInformeComplementarioDto? datos, CancellationToken ct = default)
        => Responder(await guardar.EjecutarAsync(idComplementario, datos, IdUsuarioActual, ct));

    /// <summary>Descarta un complementario en borrador (nunca guardado). Después se puede generar otro.</summary>
    [RequierePermiso("rt_editar")]
    [HttpDelete("complementarios/{idComplementario:long}")]
    public async Task<IActionResult> Descartar(long idComplementario, CancellationToken ct = default)
        => Responder(await descartar.EjecutarAsync(idComplementario, IdUsuarioActual, ct));

    /// <summary>Sube una foto (JPEG / PNG, hasta 10 MB) o un video (MP4, hasta 40 MB) al complementario. Hasta 60 por complementario.</summary>
    [RequierePermiso("rt_editar")]
    [HttpPost("complementarios/{idComplementario:long}/fotos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoSubida)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoSubida)]
    public async Task<IActionResult> SubirFoto(long idComplementario, [FromForm] FotoComplementarioFormulario f, CancellationToken ct = default)
    {
        await using var a = f.Archivo?.OpenReadStream();
        return Responder(await subirFoto.EjecutarAsync(idComplementario, a, f.Archivo?.Length ?? 0, f.Momento, f.Descripcion, f.IdObservacion, IdUsuarioActual, ct));
    }

    /// <summary>Quita una foto o video del complementario (las copiadas del original no borran el archivo del técnico).</summary>
    [RequierePermiso("rt_editar")]
    [HttpDelete("complementarios/{idComplementario:long}/fotos/{idEvidencia:long}")]
    public async Task<IActionResult> QuitarFoto(long idComplementario, long idEvidencia, CancellationToken ct = default)
        => Responder(await quitarFoto.EjecutarAsync(idComplementario, idEvidencia, IdUsuarioActual, ct));

    /// <summary>OBS #4478: edita la descripción de una foto o video que subió el supervisor (hasta 200 caracteres; null o "" la borra).
    /// Las fotos copiadas del técnico no se editan.</summary>
    [RequierePermiso("rt_editar")]
    [RequestSizeLimit(16 * 1024)]
    [HttpPatch("complementarios/{idComplementario:long}/fotos/{idEvidencia:long}/descripcion")]
    public async Task<IActionResult> ActualizarDescripcionFoto(long idComplementario, long idEvidencia,
                                                               [FromBody] ActualizarDescripcionFotoComplementarioDto? datos, CancellationToken ct = default)
        => Responder(await descripcionFoto.EjecutarAsync(idComplementario, idEvidencia, datos?.Descripcion, IdUsuarioActual, ct));

    /// <summary>El archivo de una foto o video del complementario (?cuadro=true: la miniatura del video, si la tiene). Requiere el token:
    /// el front lo pide con fetch y lo muestra con URL.createObjectURL.</summary>
    [RequierePermiso("rt_bandeja", "precot_ver")]
    [HttpGet("complementarios/{idComplementario:long}/fotos/{idEvidencia:long}/archivo")]
    public async Task<IActionResult> ArchivoFoto(long idComplementario, long idEvidencia, [FromQuery] bool cuadro, CancellationToken ct = default)
    {
        var (contenido, tipo, mensaje) = await archivoFoto.EjecutarAsync(idComplementario, idEvidencia, cuadro, IdUsuarioActual, ct);
        return contenido is null ? NotFound(new RespuestaDto<object>(1, mensaje ?? "Foto no encontrada.")) : File(contenido, tipo!, enableRangeProcessing: true);
    }

    /// <summary>PDF del informe complementario (separado del PDF del informe original). Requiere el token.</summary>
    [RequierePermiso("rt_bandeja", "precot_ver")]
    [HttpGet("complementarios/{idComplementario:long}/pdf")]
    public async Task<IActionResult> Pdf(long idComplementario, CancellationToken ct = default)
    {
        var r = await pdf.EjecutarAsync(idComplementario, IdUsuarioActual, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        Response.Headers.CacheControl = "private, no-store";
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }
}
