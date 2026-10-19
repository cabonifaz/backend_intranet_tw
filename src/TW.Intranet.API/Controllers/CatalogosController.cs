using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.API.Controllers;

/// <summary>
/// Alta de valores en catálogos (HU-86). El GET de la misma ruta
/// está en MaestrosController; aquí solo el POST.
/// </summary>
[ApiController]
[Route("api/maestros")]
[Authorize]
public class CatalogosController(AgregarItemCatalogoCasoDeUso agregarItem) : ControllerBase
{
    private long IdUsuarioActual =>
        long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : 0;

    /// <summary>
    /// Agrega un valor a TIPO_SUMINISTRO, SUBTIPO_SUMINISTRO, MARCA_SUMINISTRO o MODELO_SUMINISTRO.
    /// Body: { "string1": "RADWAG", "string2": "radwag" } (string2 opcional).
    /// Devuelve el ítem creado { id, nombre, codigo }.
    /// </summary>
    [RequierePermiso("@catalogo")]
    [HttpPost("catalogos/{descripcion}")]
    public async Task<IActionResult> AgregarItem(
        string descripcion, [FromBody] AgregarItemCatalogoDto dto, CancellationToken ct = default)
    {
        var r = await agregarItem.EjecutarAsync(descripcion, dto, IdUsuarioActual, ct);
        return r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };
    }

    /// <summary>
    /// Renombra un valor de un catálogo editable (ej. un área). Body: { "string1": "Calidad" }.
    /// El código no cambia porque otros registros lo referencian.
    /// </summary>
    [RequierePermiso("@catalogo")]
    [HttpPut("catalogos/{descripcion}/{codigo}")]
    [HttpPatch("catalogos/{descripcion}/{codigo}")]
    public async Task<IActionResult> EditarItem(
        string descripcion, string codigo, [FromBody] EditarItemCatalogoDto dto, CancellationToken ct = default)
    {
        var r = await agregarItem.EditarAsync(descripcion, codigo, dto, IdUsuarioActual, ct);
        return r.IdTipoMensaje switch
        {
            2 => Ok(r),
            1 => BadRequest(r),
            _ => StatusCode(500, r),
        };
    }
}
