namespace TW.Intranet.Aplicacion.Puertos;

public interface IVerificadorContrasena
{
    bool Verificar(string contrasenaPlana, string hash);
}
