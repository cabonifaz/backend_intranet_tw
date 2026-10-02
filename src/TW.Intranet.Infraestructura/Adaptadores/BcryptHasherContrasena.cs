using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class BcryptHasherContrasena : IHasherContrasena
{
    // Mismo costo (12) que los hashes existentes en la BD ($2a$12$...)
    public string Hash(string contrasenaPlana) =>
        BCrypt.Net.BCrypt.HashPassword(contrasenaPlana, workFactor: 12);
}
