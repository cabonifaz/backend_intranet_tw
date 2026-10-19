namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Datos del usuario autenticado (GET /api/autenticacion/me). El front los usa para
/// refrescar su sesión local cuando el admin cambia rol/área sin forzar re-login.
/// </summary>
public record MisDatosDto(
    long   IdUsuario,
    string Nombre,
    string Apellido,
    string Correo,
    string RolSistema,
    string RolSistemaLabel,
    string Area,
    bool   ForzarCambioContrasena
);
