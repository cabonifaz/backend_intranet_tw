namespace TW.Intranet.Aplicacion.Dtos;

public record IniciarSesionSalidaDto(
    string Token,
    string Nombre,
    string Apellido,
    string Correo,
    string RolSistema
);
