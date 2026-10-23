using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// App Mobile HU-04 — Detalle del servicio y checklist de pre-salida.
/// Todas las rutas validan que la OS sea del técnico del token (principal o personal): con el id
/// de otra OS se responde lo mismo que si no existiera (sin IDOR ni enumeración).
/// </summary>
[ApiController]
[Authorize]
[Route("api/movil/servicios/{idOs:long}")]
public class PresalidaMovilController(
    ObtenerDetalleServicioMovilCasoDeUso      obtenerDetalle,
    ObtenerChecklistSalidaMovilCasoDeUso      obtenerChecklist,
    MarcarItemChecklistSalidaMovilCasoDeUso   marcarItem,
    SolicitarAutorizacionSalidaMovilCasoDeUso solicitarAutorizacion,
    IniciarTrasladoMovilCasoDeUso             iniciarTraslado,
    ILogger<PresalidaMovilController>         logger) : ControladorAppMovil(logger)
{
    /// <summary>Detalle: destino, contacto, documentos, alertas, riesgos, repuestos e historial.</summary>
    [HttpGet]
    public async Task<IActionResult> ObtenerDetalle(long idOs, CancellationToken ct)
        => Responder(await obtenerDetalle.EjecutarAsync(IdUsuarioActual, idOs, ct), StatusCodes.Status404NotFound);

    /// <summary>Checklist de pre-salida con el estado de cada ítem y si se puede iniciar el traslado.</summary>
    [HttpGet("checklist")]
    public async Task<IActionResult> ObtenerChecklist(long idOs, CancellationToken ct)
        => Responder(await obtenerChecklist.EjecutarAsync(IdUsuarioActual, idOs, ct), StatusCodes.Status404NotFound);

    /// <summary>Confirma o desmarca un ítem manual: expediente, epp, materiales, herramientas o pesas_patron.</summary>
    [HttpPut("checklist/{codigo}")]
    [RequestSizeLimit(1024)]
    public async Task<IActionResult> MarcarItem(long idOs, string codigo, [FromBody] MarcarItemChecklistDto dto, CancellationToken ct)
        => Responder(await marcarItem.EjecutarAsync(IdUsuarioActual, idOs, codigo, dto, ct));

    /// <summary>Pide el visto bueno al encargado del área del servicio según la RQ (solo si hay pendientes).</summary>
    [HttpPost("solicitar-autorizacion")]
    [RequestSizeLimit(2 * 1024)]
    public async Task<IActionResult> SolicitarAutorizacion(long idOs, [FromBody] SolicitarAutorizacionSalidaDto? dto, CancellationToken ct)
    {
        var r = await solicitarAutorizacion.EjecutarAsync(IdUsuarioActual, idOs, dto, ct);
        if (r.IdTipoMensaje == 2)
            logger.LogInformation("App móvil: solicitud de autorización de salida OS {IdOs} por usuario {IdUsuario}", idOs, IdUsuarioActual);
        return Responder(r);
    }

    /// <summary>Inicia el traslado (la OS pasa a "en ruta"). El back vuelve a validar el checklist.</summary>
    [HttpPost("iniciar-traslado")]
    public async Task<IActionResult> IniciarTraslado(long idOs, CancellationToken ct)
    {
        var r = await iniciarTraslado.EjecutarAsync(IdUsuarioActual, idOs, ct);
        if (r.IdTipoMensaje == 2)
            logger.LogInformation("App móvil: inicio de traslado OS {IdOs} por usuario {IdUsuario}", idOs, IdUsuarioActual);
        return Responder(r);
    }
}
