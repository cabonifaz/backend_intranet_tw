namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// Parámetros JWT registrados como singleton en DI.
/// Usados tanto por JwtServicio (generación) como por Program.cs (validación del middleware).
/// </summary>
public record ConfiguracionJwt(
    string Secret,
    int    ExpirationHours,
    string Issuer,
    string Audience
);
