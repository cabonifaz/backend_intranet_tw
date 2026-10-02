using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Dominio.Entidades;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class JwtServicio(ConfiguracionJwt config) : IJwtServicio
{
    public string GenerarToken(Usuario usuario)
    {
        var clave        = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config.Secret));
        var credenciales = new SigningCredentials(clave, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub,   usuario.IdUsuario.ToString()),
            new Claim(JwtRegisteredClaimNames.Email, usuario.Correo),
            new Claim(JwtRegisteredClaimNames.Jti,   Guid.NewGuid().ToString()),
            new Claim("nombre",       usuario.Nombre),
            new Claim("apellido",     usuario.Apellido),
            new Claim("rol",          usuario.RolSistema),
            new Claim("sesion_token", usuario.SesionToken),
        };

        var token = new JwtSecurityToken(
            issuer:             config.Issuer,
            audience:           config.Audience,
            claims:             claims,
            expires:            DateTime.UtcNow.AddHours(config.ExpirationHours),
            signingCredentials: credenciales);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
