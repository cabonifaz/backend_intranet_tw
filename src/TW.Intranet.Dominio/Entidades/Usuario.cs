namespace TW.Intranet.Dominio.Entidades;

public class Usuario
{
    public long   IdUsuario    { get; init; }
    public string Nombre       { get; init; } = string.Empty;
    public string Apellido     { get; init; } = string.Empty;
    public string Correo       { get; init; } = string.Empty;
    public string PasswordHash { get; init; } = string.Empty;
    public string RolSistema   { get; init; } = string.Empty;
    public string CanalAcceso  { get; init; } = string.Empty;
    public string Estado       { get; init; } = string.Empty;
}
