using TW.Intranet.Dominio.Entidades;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IJwtServicio
{
    string GenerarToken(Usuario usuario);

    /// <summary>JWT de la app móvil: lleva claim canal = movil y vence en la fecha de la sesión.</summary>
    string GenerarTokenMovil(Usuario usuario, string sesionToken, DateTime expiraUtc);
}
