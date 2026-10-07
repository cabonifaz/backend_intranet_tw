namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Acceso a un módulo para una combinación ÁREA + ROL (reunión 02-oct).
/// Acceso: ninguno | ver | editar | supervisar | administrar.
/// EsExcepcion = true si viene de la tabla de excepciones (no de la regla general).
/// </summary>
public record PermisoModuloDto(
    string Modulo,
    string ModuloLabel,
    string AreaModulo,
    string Acceso,
    bool   EsExcepcion);

/// <summary>Body de PUT /api/maestros/permisos. Acceso vacío = volver a la regla general.</summary>
public class GuardarPermisoDto
{
    public string? Area   { get; set; }
    public string? Rol    { get; set; }
    public string? Modulo { get; set; }
    public string? Acceso { get; set; }
}

/// <summary>Acción del sistema y si el usuario puede ejecutarla (ticket #4301).</summary>
public record AccionPermitidaDto(
    string Accion,
    string AccionLabel,
    string Modulo,
    string NivelRequerido,
    bool   Permitido);
