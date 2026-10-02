namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Ficha completa del usuario (HU-83). Coincide con UsuarioDetalle del front.</summary>
public record UsuarioDetalleDto(
    // Datos del listado
    long      IdUsuario,
    string    Nombre,
    string    Apellido,
    string    Correo,
    string    RolSistema,
    string    RolSistemaLabel,
    string?   Area,
    string?   Telefono,
    string    Estado,
    DateTime? UltimoAcceso,
    DateTime? FechaCreacion,

    // 01 Información personal
    string    TipoDocumento,
    string    NumeroDocumento,
    string?   Cargo,

    // 02 Asignación operativa
    /// <summary>Código de SEDE_OPERATIVA_TW (ej. "lima_central").</summary>
    string?   SedeOperativa,
    long?     IdSupervisorDirecto,

    // 03 Certificación técnica
    bool      HabilitadoFirmaInacal,
    string?   NumeroRegistroInacal,
    string?   FechaExpiracionCertificacion,
    bool      RequiereInduccionSctr,

    // 04 Seguridad
    bool      ForzarCambioContrasena,
    bool      EnviarCredencialesCorreo,
    bool      Autenticacion2fa
);
