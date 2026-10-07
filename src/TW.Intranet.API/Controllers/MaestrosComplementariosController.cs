using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>Correcciones de la reunión 02-oct: ubigeo, áreas del cliente, códigos de formato y próximo código de ficha.</summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class MaestrosComplementariosController(
    ObtenerUbigeoCasoDeUso                 obtenerUbigeo,
    ObtenerAreasClienteCasoDeUso           obtenerAreas,
    GuardarAreaClienteCasoDeUso            guardarArea,
    CambiarEstadoAreaClienteCasoDeUso      cambiarEstadoArea,
    ObtenerSiguienteCodigoCasoDeUso        obtenerSiguienteCodigo,
    ObtenerFormatosVentanaCasoDeUso        obtenerFormatos,
    GuardarFormatoVentanaCasoDeUso         guardarFormato,
    ObtenerRequisitosDelClienteCasoDeUso   obtenerRequisitosCliente,
    SincronizarRequisitosClienteCasoDeUso  sincronizarRequisitosCliente) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    private IActionResult Responder<T>(RespuestaDto<T> r) =>
        r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };

    // ── Ubigeo INEI (cascada para sedes) ─────────────────────────────────────
    [HttpGet("ubigeo/departamentos")]
    public async Task<IActionResult> Departamentos(CancellationToken ct = default)
        => Responder(await obtenerUbigeo.EjecutarAsync("departamentos", null, null, ct));

    [HttpGet("ubigeo/provincias")]
    public async Task<IActionResult> Provincias([FromQuery] string? departamento, CancellationToken ct = default)
        => Responder(await obtenerUbigeo.EjecutarAsync("provincias", departamento, null, ct));

    [HttpGet("ubigeo/distritos")]
    public async Task<IActionResult> Distritos([FromQuery] string? departamento, [FromQuery] string? provincia, CancellationToken ct = default)
        => Responder(await obtenerUbigeo.EjecutarAsync("distritos", departamento, provincia, ct));

    // ── Áreas por cliente (nombres libres, estado activo/inactivo) ───────────
    [HttpGet("clientes/{idCliente:long}/areas")]
    public async Task<IActionResult> Areas(long idCliente, [FromQuery] bool soloActivas = true, CancellationToken ct = default)
        => Responder(await obtenerAreas.EjecutarAsync(idCliente, soloActivas, ct));

    [RequierePermiso("cliente_areas_requisitos")]
    [HttpPost("clientes/{idCliente:long}/areas")]
    public async Task<IActionResult> GuardarArea(long idCliente, [FromBody] GuardarAreaClienteDto dto, CancellationToken ct = default)
        => Responder(await guardarArea.EjecutarAsync(idCliente, dto, IdUsuarioActual, ct));

    [RequierePermiso("cliente_areas_requisitos")]
    [HttpPatch("areas-cliente/{idArea:long}/estado")]
    public async Task<IActionResult> CambiarEstadoArea(long idArea, [FromBody] CambiarEstadoAreaClienteDto dto, CancellationToken ct = default)
        => Responder(await cambiarEstadoArea.EjecutarAsync(idArea, dto, IdUsuarioActual, ct));

    // ── Requisitos SSOMA asignados al cliente ────────────────────────────────
    [HttpGet("clientes/{idCliente:long}/requisitos-ssoma")]
    public async Task<IActionResult> RequisitosDelCliente(long idCliente, CancellationToken ct = default)
        => Responder(await obtenerRequisitosCliente.EjecutarAsync(idCliente, ct));

    [RequierePermiso("cliente_areas_requisitos")]
    [HttpPut("clientes/{idCliente:long}/requisitos-ssoma")]
    public async Task<IActionResult> SincronizarRequisitosCliente(long idCliente, [FromBody] SincronizarRequisitosSsomaDto dto, CancellationToken ct = default)
        => Responder(await sincronizarRequisitosCliente.EjecutarAsync(idCliente, dto, IdUsuarioActual, ct));

    // ── Próximo código de la ficha en modo "nuevo" (referencial) ─────────────
    /// <summary>entidad: requerimiento | propuesta | suministro | equipo_cliente → { entidad, codigo }.</summary>
    [HttpGet("siguiente-codigo/{entidad}")]
    public async Task<IActionResult> SiguienteCodigo(string entidad, CancellationToken ct = default)
        => Responder(await obtenerSiguienteCodigo.EjecutarAsync(entidad, ct));

    // ── Códigos de formato por ventana ───────────────────────────────────────
    [HttpGet("formatos-ventana")]
    public async Task<IActionResult> Formatos([FromQuery] string? clave, CancellationToken ct = default)
        => Responder(await obtenerFormatos.EjecutarAsync(clave, ct));

    [RequierePermiso("formato_ventana_guardar")]
    [HttpPut("formatos-ventana/{clave}")]
    public async Task<IActionResult> GuardarFormato(string clave, [FromBody] GuardarFormatoVentanaDto dto, CancellationToken ct = default)
        => Responder(await guardarFormato.EjecutarAsync(clave, dto, IdUsuarioActual, ct));
}
