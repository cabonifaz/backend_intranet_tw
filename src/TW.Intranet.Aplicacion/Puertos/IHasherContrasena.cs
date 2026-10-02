namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Genera el hash de una contraseña para guardarla en la BD.</summary>
public interface IHasherContrasena
{
    string Hash(string contrasenaPlana);
}
