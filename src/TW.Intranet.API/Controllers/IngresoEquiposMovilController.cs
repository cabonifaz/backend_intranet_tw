using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-22 — Ingreso de equipos (OS): el técnico registra el ingreso de un equipo de su OS (estado de ingreso, observación y fotos si no está operativo).
/// La lista de equipos, la búsqueda, el QR y el equipo nuevo son los de HU-07 (<c>api/movil/servicios/{idOs}/objetivos</c>, <c>equipos/qr</c>, <c>equipos/nuevo</c>).
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}/ingresos")]
public class IngresoEquiposMovilController(
    ObtenerIngresosEquiposMovilCasoDeUso   obtener,
    RegistrarIngresoEquipoMovilCasoDeUso   registrar,
    ILogger<IngresoEquiposMovilController> logger) : ControladorAppMovil(logger)
{
    /// <summary>5 fotos de hasta 5 MB + margen del formulario.</summary>
    private const long TamanoMaximoPeticion = 5 * 5 * 1024 * 1024 + 512 * 1024;

    /// <summary>Formulario multipart del ingreso: estado, observación y fotos de evidencia (JPEG de la cámara).</summary>
    public class IngresoFormulario
    {
        public string? Estado { get; set; }
        public string? Observacion { get; set; }
        public List<IFormFile>? Fotos { get; set; }
    }

    /// <summary>Equipos de la OS que ya se ingresaron (estado, observación y hora). El técnico sale del token.</summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(long idOs, CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, idOs, ct));

    /// <summary>
    /// Registra el ingreso de un equipo. Con observaciones o inoperativo exige observación y al menos una foto. Un equipo no se ingresa dos veces en la misma OS.
    /// </summary>
    [HttpPost("equipos/{idOsEquipo:long}")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Registrar(long idOs, long idOsEquipo, [FromForm] IngresoFormulario f, CancellationToken ct)
    {
        var abiertos = new List<Stream>();
        try
        {
            var fotos = new List<(Stream, long)>();
            foreach (var foto in f.Fotos ?? [])
            {
                var s = foto.OpenReadStream();
                abiertos.Add(s);
                fotos.Add((s, foto.Length));
            }
            return Responder(await registrar.EjecutarAsync(IdUsuarioActual, idOs, idOsEquipo, f.Estado, f.Observacion, fotos, ct));
        }
        finally
        {
            foreach (var s in abiertos) await s.DisposeAsync();
        }
    }
}
