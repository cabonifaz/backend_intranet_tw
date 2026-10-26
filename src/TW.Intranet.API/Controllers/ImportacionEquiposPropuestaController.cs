using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Propuestas — Importación masiva del listado de equipos desde Excel con IA (Sprint 4).
/// 1) POST analizar: lee el Excel y concilia (no guarda). 2) El comercial revisa. 3) POST confirmar: crea los equipos
/// nuevos en el inventario del cliente y devuelve la lista para el listado de equipos de la propuesta (que se guarda
/// con la propuesta, como siempre). Sirve también para propuestas nuevas (aún sin id).
/// </summary>
[ApiController]
[Route("api/crm/propuestas/equipos/importacion")]
[Authorize]
public class ImportacionEquiposPropuestaController(
    AnalizarImportacionEquiposCasoDeUso            analizar,
    ConfirmarImportacionEquiposCasoDeUso           confirmar,
    DescargarPlantillaImportacionEquiposCasoDeUso  plantilla,
    ExportarReporteImportacionEquiposCasoDeUso     reporte) : ControllerBase
{
    private const long TamanoMaximoPeticion = 6 * 1024 * 1024;

    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id) ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) => r.IdTipoMensaje switch
    {
        2 => Ok(r),
        1 => BadRequest(r),
        _ => StatusCode(500, r),
    };

    /// <summary>Plantilla .xlsx sugerida (el formato es libre: la IA reconoce las columnas).</summary>
    [RequierePermiso("propuesta_guardar")]
    [HttpGet("plantilla")]
    public IActionResult DescargarPlantilla()
    {
        var a = plantilla.Ejecutar();
        return File(a.Contenido, a.TipoContenido, a.NombreArchivo);
    }

    /// <summary>
    /// Analiza el Excel (multipart): archivo (.xlsx o .csv, máx. 5 MB y 500 equipos), idCliente, idSede (sede por
    /// defecto para los equipos nuevos: la del requerimiento), idsEquipoEnPropuesta y seriesEnPropuesta (repetidos,
    /// lo que ya está en el listado de la propuesta, para no duplicarlo). No guarda nada.
    /// </summary>
    [RequierePermiso("propuesta_guardar")]
    [HttpPost("analizar")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(TamanoMaximoPeticion)]
    [RequestFormLimits(MultipartBodyLengthLimit = TamanoMaximoPeticion)]
    public async Task<IActionResult> Analizar(
        IFormFile? archivo,
        [FromForm] long idCliente,
        [FromForm] long? idSede,
        [FromForm] List<long>? idsEquipoEnPropuesta,
        [FromForm] List<string>? seriesEnPropuesta,
        CancellationToken ct = default)
    {
        if (archivo is null || archivo.Length == 0)
            return BadRequest(new RespuestaDto<object>(1, "Adjunte el archivo Excel con el listado de equipos."));

        var solicitud = new AnalizarImportacionEquiposSolicitudDto(
            idCliente, idSede, idsEquipoEnPropuesta ?? [],
            (seriesEnPropuesta ?? []).Where(s => !string.IsNullOrWhiteSpace(s)).ToList());

        await using var contenido = archivo.OpenReadStream();
        return Responder(await analizar.EjecutarAsync(contenido, archivo.FileName, archivo.Length, solicitud, IdUsuarioActual, ct));
    }

    /// <summary>
    /// Confirma la importación: { idCliente, filas: [{ fila, accion: vincular | crear, idEquipo, numSerie, marca,
    /// modelo, clasificacion, idSuministro, idSede, codigoCliente, ubicacion, alcanceMaximo }] }. Todo o nada.
    /// </summary>
    [RequierePermiso("propuesta_guardar")]
    [HttpPost("confirmar")]
    public async Task<IActionResult> Confirmar([FromBody] ConfirmarImportacionEquiposSolicitudDto? solicitud, CancellationToken ct = default)
        => Responder(await confirmar.EjecutarAsync(solicitud, IdUsuarioActual, ct));

    /// <summary>Reporte .xlsx de la conciliación: body = las filas de la vista previa (con las correcciones del comercial).</summary>
    [RequierePermiso("propuesta_guardar")]
    [HttpPost("reporte")]
    public IActionResult Reporte([FromBody] List<FilaImportacionEquipoDto>? filas)
    {
        var r = reporte.Ejecutar(filas);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return Responder(r);
        return File(r.Datos.Contenido, r.Datos.TipoContenido, r.Datos.NombreArchivo);
    }
}
