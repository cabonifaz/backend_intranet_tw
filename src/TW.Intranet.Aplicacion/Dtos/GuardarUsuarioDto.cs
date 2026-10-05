namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Body de POST /api/maestros/usuarios. IdUsuario = 0 para crear.</summary>
public class GuardarUsuarioDto
{
    public long      IdUsuario       { get; set; }
    public string?   Nombre          { get; set; }
    public string?   Apellido        { get; set; }
    public string?   TipoDocumento   { get; set; }
    public string?   NumeroDocumento { get; set; }
    public string?   Correo          { get; set; }
    public string?   Telefono        { get; set; }
    /// <summary>Anexo telefónico interno (solo números, hasta 10). Centrales: 569-9750 / 569-9751.</summary>
    public string?   Anexo           { get; set; }
    /// <summary>Fecha de nacimiento (yyyy-MM-dd). Uso interno (RR. HH.).</summary>
    public string?   FechaNacimiento { get; set; }
    public string?   Cargo           { get; set; }
    /// <summary>Código de AREA_USUARIO (ej. "comercial").</summary>
    public string?   Area            { get; set; }
    public string?   RolSistema      { get; set; }
    /// <summary>Código de SEDE_OPERATIVA_TW. Si no se envía: "lima_central".</summary>
    public string?   SedeOperativa   { get; set; }
    public long?     IdSupervisorDirecto { get; set; }

    public bool      HabilitadoFirmaInacal        { get; set; }
    public string?   NumeroRegistroInacal         { get; set; }
    public string?   FechaExpiracionCertificacion { get; set; }
    public bool      RequiereInduccionSctr        { get; set; }

    /// <summary>Obligatoria al crear. En edición, vacía = no se cambia la contraseña.</summary>
    public string?   ContrasenaTemporal       { get; set; }
    public bool      ForzarCambioContrasena   { get; set; }
    public bool      EnviarCredencialesCorreo { get; set; }
    public bool      Autenticacion2fa         { get; set; }
    public bool      GuardarComoBorrador      { get; set; }
}
