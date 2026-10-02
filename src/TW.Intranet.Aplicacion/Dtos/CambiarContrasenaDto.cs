namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Body de POST /api/autenticacion/cambiar-contrasena.
/// El idUsuario se toma del JWT, no viene en el body.
/// </summary>
public record CambiarContrasenaDto(
    string ContrasenaActual,
    string ContrasenaNueva
);
