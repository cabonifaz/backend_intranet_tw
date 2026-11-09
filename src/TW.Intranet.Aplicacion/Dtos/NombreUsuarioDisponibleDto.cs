namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Respuesta de GET /api/maestros/usuarios/validar-nombre-usuario (ficha de usuario).</summary>
public record NombreUsuarioDisponibleDto(
    bool    Disponible,
    /// <summary>Variante libre (ej. "juan.perez2") cuando el nombre está en uso.</summary>
    string? Sugerencia = null
);
