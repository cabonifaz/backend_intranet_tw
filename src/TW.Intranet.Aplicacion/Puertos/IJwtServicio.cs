using TW.Intranet.Dominio.Entidades;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IJwtServicio
{
    string GenerarToken(Usuario usuario);
}
