using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>App Mobile HU-25 / HU-26 / HU-27 — Viáticos asignados al programar, gastos rendidos del técnico y rendir un gasto desde la app.</summary>
[ApiController]
[Authorize]
[Route("api/movil/viaticos")]
public class ViaticosMovilController(
    ObtenerViaticosMovilCasoDeUso    obtener,
    RendirGastoMovilCasoDeUso        rendir,
    ObtenerConceptosGastoMovilCasoDeUso conceptos,
    ObtenerFotoGastoMovilCasoDeUso   foto,
    ILogger<ViaticosMovilController> logger) : ControladorAppMovil(logger)
{
    /// <summary>Hasta 5 fotos de 5 MB más el JSON: margen para el multipart.</summary>
    private const long TamanoMaximoPeticion = 27 * 1024 * 1024;

    /// <summary>
    /// Multipart de un gasto: "datos" = JSON { idCliente, origen (viatico | reembolso), idOs, idConcepto, conceptoTexto, monto, fechaGasto (yyyy-MM-dd),
    /// descripcion, reparto [{ idViaticoLinea, monto }], motivoSinFoto, fotosConservar }; "fotos" = hasta 5 JPEG de máximo 5 MB.
    /// Al corregir, fotosConservar también puede llegar como campo propio ("[1,3]" o "1,3").
    /// </summary>
    public class GastoFormulario
    {
        public string?           Datos          { get; set; }
        public string?           FotosConservar { get; set; }
        public List<IFormFile>?  Fotos          { get; set; }
    }

    /// <summary>
    /// Resumen (saldo por rendir y gastos en revisión), viáticos por programación, adelanto por concepto (con idViaticoLinea para el reparto),
    /// gastos rendidos, su reparto y sus fotos, del técnico que inició sesión. El técnico sale del token: nadie puede pedir los de otro.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Obtener(CancellationToken ct)
        => Responder(await obtener.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>HU-27 Conceptos del catálogo de la intranet para elegir en un reembolso ("Otro" pide el texto).</summary>
    [HttpGet("conceptos")]
    public async Task<IActionResult> Conceptos(CancellationToken ct)
        => Responder(await conceptos.EjecutarAsync(IdUsuarioActual, ct));

    /// <summary>
    /// HU-27 Rendir un gasto (del adelanto con reparto, o reembolso) en una sola petición con sus fotos. Un reintento con el mismo idCliente devuelve el
    /// gasto ya creado (duplicado = true) sin crear otro. Las líneas que se pasan de lo que les queda no se rechazan: vuelven como advertencias.
    /// </summary>
    [HttpPost("gastos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public Task<IActionResult> Rendir([FromForm] GastoFormulario f, CancellationToken ct)
        => GuardarAsync(0, f, ct);

    /// <summary>HU-27 Corregir un gasto observado: mismo formato, más fotosConservar (orden de las fotos que se quedan). Vuelve a la revisión del jefe.</summary>
    [HttpPut("gastos/{idGasto:long}")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public Task<IActionResult> Corregir(long idGasto, [FromForm] GastoFormulario f, CancellationToken ct)
        => GuardarAsync(idGasto, f, ct);

    /// <summary>Foto n (1 a 5) de un gasto propio (JPEG). La app la pide con el token y la muestra como blob.</summary>
    [HttpGet("gastos/{idGasto:long}/fotos/{n:int}")]
    public async Task<IActionResult> Foto(long idGasto, int n, CancellationToken ct)
    {
        var (contenido, tipo, mensaje) = await foto.EjecutarAsync(IdUsuarioActual, idGasto, n, ct);
        if (contenido is null) return NotFound(new RespuestaDto<object>(1, mensaje ?? "Foto no encontrada."));
        Response.Headers.CacheControl = "private, no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return File(contenido, tipo!);
    }

    private async Task<IActionResult> GuardarAsync(long idGasto, GastoFormulario f, CancellationToken ct)
    {
        var archivos = f.Fotos ?? [];
        if (archivos.Count > EntradaGastoMovil.MaxFotos)
            return Responder(new RespuestaDto<ResultadoGastoMovilDto>(1, $"Un gasto admite hasta {EntradaGastoMovil.MaxFotos} fotos."));
        var streams = new List<Stream>();
        try
        {
            var fotos = new List<(Stream, long)>();
            foreach (var a in archivos)
            {
                var s = a.OpenReadStream();
                streams.Add(s);
                fotos.Add((s, a.Length));
            }
            return Responder(await rendir.EjecutarAsync(IdUsuarioActual, idGasto, f.Datos, f.FotosConservar, fotos, ct));
        }
        finally
        {
            foreach (var s in streams) await s.DisposeAsync();
        }
    }
}
