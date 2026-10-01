namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de usuarios (HU-82). Coincide con UsuarioListaItem del front.</summary>
public record UsuarioListaItemDto(
    long      IdUsuario,
    string    Nombre,
    string    Apellido,
    string    Correo,
    string    RolSistema,
    string    RolSistemaLabel,
    string?   AreaComercial,
    string?   Telefono,
    string    Estado,
    DateTime? UltimoAcceso,
    DateTime? FechaCreacion
);
