namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Ítem de catálogo de tabla_maestra.
/// Num2 y String3 son opcionales (p.ej. CARGO_USUARIO los usa para indicar el área del cargo).
/// </summary>
public record CatalogoItemDto(
    int      Id,
    string   Nombre,
    string?  Codigo,
    decimal? Num2    = null,
    string?  String3 = null
);
