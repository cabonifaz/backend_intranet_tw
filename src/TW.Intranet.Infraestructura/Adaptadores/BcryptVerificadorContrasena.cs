using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class BcryptVerificadorContrasena : IVerificadorContrasena
{
    public bool Verificar(string contrasenaPlana, string hash) =>
        BCrypt.Net.BCrypt.Verify(contrasenaPlana, hash);
}
