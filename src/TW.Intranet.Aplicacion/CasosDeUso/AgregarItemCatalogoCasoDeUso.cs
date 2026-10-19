using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Agrega un valor a un catálogo de tabla_maestra desde el front
/// (modales "Nuevo Tipo / Subtipo / Marca / Modelo" de Suministros, HU-86,
/// "Nueva forma de pago" de la Propuesta, HU-07, y "Nueva área" de Usuarios).
/// </summary>
public class AgregarItemCatalogoCasoDeUso(ICatalogosRepositorio repositorio)
{
    /// <summary>
    /// Catálogos que el usuario puede ampliar desde la aplicación.
    /// Los demás (roles, estados, etc.) solo se modifican por migración.
    /// </summary>
    private static readonly HashSet<string> CatalogosEditables = new(StringComparer.OrdinalIgnoreCase)
    {
        "TIPO_SUMINISTRO",
        "SUBTIPO_SUMINISTRO",
        "MARCA_SUMINISTRO",
        "MODELO_SUMINISTRO",
        "CONDICION_PAGO",       // HU-07: botón "Nuevo" en Forma de Pago
        "AREA_USUARIO",         // Reunión 02-oct: TW crea áreas nuevas (restringir por rol en el front)
    };

    public async Task<RespuestaDto<CatalogoItemDto>> EjecutarAsync(
        string descripcion, AgregarItemCatalogoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (!CatalogosEditables.Contains(descripcion))
            return new RespuestaDto<CatalogoItemDto>(1, $"El catálogo '{descripcion}' no admite nuevos valores desde la aplicación.");

        var etiqueta = dto.String1?.Trim();
        if (string.IsNullOrWhiteSpace(etiqueta))
            return new RespuestaDto<CatalogoItemDto>(1, "El nombre es obligatorio.");

        if (etiqueta.Length > 100)
            return new RespuestaDto<CatalogoItemDto>(1, "El nombre no puede superar los 100 caracteres.");

        var codigo = string.IsNullOrWhiteSpace(dto.String2) ? GenerarCodigo(etiqueta) : dto.String2.Trim();
        if (string.IsNullOrWhiteSpace(codigo))
            return new RespuestaDto<CatalogoItemDto>(1, "No se pudo generar un código válido para ese nombre.");

        var catalogo = descripcion.ToUpperInvariant();
        var string3  = string.IsNullOrWhiteSpace(dto.String3) ? null : dto.String3.Trim().ToLowerInvariant();
        // TIPO_SUMINISTRO: String3 = clase del tipo. Si no se envía, el tipo queda visible para todas las clases.
        return await repositorio.AgregarItemAsync(catalogo, etiqueta, codigo, string3, idUsuario, ct);
    }

    /// <summary>Cambia el nombre visible de un valor (el código no cambia). Mismos catálogos editables.</summary>
    public async Task<RespuestaDto<CatalogoItemDto>> EditarAsync(
        string descripcion, string codigo, EditarItemCatalogoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (!CatalogosEditables.Contains(descripcion))
            return new RespuestaDto<CatalogoItemDto>(1, $"El catálogo '{descripcion}' no se puede editar desde la aplicación.");

        var etiqueta = dto.String1?.Trim();
        if (string.IsNullOrWhiteSpace(etiqueta))
            return new RespuestaDto<CatalogoItemDto>(1, "El nombre es obligatorio.");
        if (etiqueta.Length > 100)
            return new RespuestaDto<CatalogoItemDto>(1, "El nombre no puede superar los 100 caracteres.");

        return await repositorio.EditarItemAsync(descripcion.ToUpperInvariant(), codigo.Trim(), etiqueta, idUsuario, ct);
    }

    /// <summary>Misma regla que el front: minúsculas, espacios → "_", sin símbolos ("Rice Lake" → "rice_lake").</summary>
    private static string GenerarCodigo(string texto)
    {
        var sinTildes = new StringBuilder();
        foreach (var c in texto.Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sinTildes.Append(c);

        var codigo = Regex.Replace(sinTildes.ToString().ToLowerInvariant(), @"\s+", "_");
        return Regex.Replace(codigo, "[^a-z0-9_]", "");
    }
}
