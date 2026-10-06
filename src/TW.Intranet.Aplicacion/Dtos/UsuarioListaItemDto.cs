namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de usuarios (HU-82). Coincide con UsuarioListaItem del front.</summary>
public record UsuarioListaItemDto(
    long      IdUsuario,
    string    Nombre,
    string    Apellido,
    string    Correo,
    string    RolSistema,
    string    RolSistemaLabel,
    /// <summary>Código de AREA_USUARIO (ej. "comercial").</summary>
    string?   Area,
    string?   Telefono,
    string    Estado,
    DateTime? UltimoAcceso,
    DateTime? FechaCreacion,
    /// <summary>Anexo completo: troncal + interno (ej. "5699750207").</summary>
    string?   Anexo = null,
    /// <summary>Troncal del anexo (5699750 / 5699751).</summary>
    string?   Troncal = null
);
