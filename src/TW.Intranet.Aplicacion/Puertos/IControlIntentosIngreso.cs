namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// App Mobile — Desarrollo seguro: bloqueo temporal por intentos fallidos de ingreso
/// (protección contra fuerza bruta y relleno de credenciales, OWASP ASVS V2.2).
/// La clave es el usuario escrito (exista o no), así no se revela qué usuarios existen.
/// </summary>
public interface IControlIntentosIngreso
{
    /// <summary>Tiempo que falta para poder intentar de nuevo; null si no está bloqueado.</summary>
    TimeSpan? TiempoBloqueoRestante(string clave);

    /// <summary>Suma un intento fallido; al llegar al máximo bloquea la clave.</summary>
    void RegistrarFallo(string clave);

    /// <summary>Ingreso correcto: borra los intentos fallidos.</summary>
    void Reiniciar(string clave);
}
