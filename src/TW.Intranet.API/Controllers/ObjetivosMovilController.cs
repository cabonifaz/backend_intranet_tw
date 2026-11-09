using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-07 — Lista de objetivos de la OS y selección de equipos (buscar, escanear QR, equipo nuevo, iniciar / pausar / reanudar).</summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}")]
public class ObjetivosMovilController(
    ObtenerObjetivosMovilCasoDeUso             obtener,
    BuscarEquipoQrMovilCasoDeUso               buscarQr,
    CambiarEstadoEquipoMovilCasoDeUso          cambiarEstado,
    ObtenerOpcionesEquipoNuevoMovilCasoDeUso   opciones,
    RegistrarEquipoNuevoMovilCasoDeUso         registrarNuevo,
    ILogger<ObjetivosMovilController>          logger) : ControladorAppMovil(logger)
{
    private const long TamanoMaximoPeticion = 6 * 1024 * 1024;

    /// <summary>Formulario multipart de "Equipo nuevo". La foto de la placa es obligatoria y solo JPEG de la cámara.</summary>
    public class RegistrarEquipoNuevoFormulario
    {
        public string? NumeroSerie { get; set; }
        public string? Codigo      { get; set; }
        public string? Marca       { get; set; }
        public string? Modelo      { get; set; }
        public long    IdSuministro { get; set; }
        public string? Ubicacion   { get; set; }
        public IFormFile? Foto     { get; set; }
    }

    /// <summary>
    /// Objetivos de la OS del técnico (el usuario sale del token): resumen y tiempos, contadores, equipos numerados con su estado y lo que se puede hacer
    /// con cada uno. ?buscar= filtra la lista por N/S, código, COD TW, marca, modelo, ubicación o tipo (los contadores no cambian).
    /// Sin llegada registrada (Hard Stop) responde 400 con el motivo.
    /// </summary>
    [HttpGet("objetivos")]
    public async Task<IActionResult> Obtener(long idOs, [FromQuery] string? buscar, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, buscar, ct));

    /// <summary>Equipo de la OS que corresponde a lo escaneado (N/S, código del cliente o COD TW). Si no es de la OS responde 400.</summary>
    [HttpGet("equipos/qr")]
    public async Task<IActionResult> BuscarQr(long idOs, [FromQuery] string? codigo, CancellationToken ct)
        => Responder(await buscarQr.EjecutarAsync(IdUsuarioActual, idOs, codigo, ct));

    /// <summary>"Trabajar en el equipo": inicia el trabajo (un solo equipo a la vez). Devuelve los objetivos actualizados.</summary>
    [HttpPost("equipos/{idOsEquipo:long}/iniciar")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Iniciar(long idOs, long idOsEquipo, [FromBody] PeticionCambioEstadoEquipoMovilDto? d, CancellationToken ct)
        => Responder(await cambiarEstado.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, "iniciar", d, ct));

    /// <summary>"Pausar": exige un motivo (3 a 300 caracteres). Devuelve los objetivos actualizados.</summary>
    [HttpPost("equipos/{idOsEquipo:long}/pausar")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Pausar(long idOs, long idOsEquipo, [FromBody] PeticionCambioEstadoEquipoMovilDto? d, CancellationToken ct)
        => Responder(await cambiarEstado.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, "pausar", d, ct));

    /// <summary>"Reanudar": solo un equipo pausado que no espera la aprobación de un supervisor. Devuelve los objetivos actualizados.</summary>
    [HttpPost("equipos/{idOsEquipo:long}/reanudar")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> Reanudar(long idOs, long idOsEquipo, [FromBody] PeticionCambioEstadoEquipoMovilDto? d, CancellationToken ct)
        => Responder(await cambiarEstado.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, "reanudar", d, ct));

    /// <summary>Listas del formulario "Equipo nuevo": marcas y tipos de equipo.</summary>
    [HttpGet("equipos/nuevo/opciones")]
    public async Task<IActionResult> Opciones(long idOs, CancellationToken ct)
        => Responder(await opciones.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>
    /// Registra un equipo nuevo (NEW) que no está en la lista de la OS. Queda pendiente de aprobación en la intranet, que asigna el COD TW definitivo.
    /// La foto de la placa es obligatoria (solo cámara, JPEG, hasta 5 MB).
    /// </summary>
    [HttpPost("equipos/nuevo")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> RegistrarNuevo(long idOs, [FromForm] RegistrarEquipoNuevoFormulario f, CancellationToken ct)
    {
        var dto = new NuevoEquipoMovilDto(f.NumeroSerie, f.Codigo, f.Marca, f.Modelo, f.IdSuministro, f.Ubicacion);
        await using var contenido = f.Foto?.OpenReadStream();
        return Responder(await registrarNuevo.EjecutarAsync(IdUsuarioActual, idOs, dto, contenido, f.Foto?.Length ?? 0, ct));
    }
}
