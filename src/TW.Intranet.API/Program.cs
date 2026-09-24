using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Adaptadores;
using TW.Intranet.Infraestructura.Configuracion;

var builder = WebApplication.CreateBuilder(args);

// Carga appsettings.Local.json si existe (para desarrollo local, no se sube a git)
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);

// ── CORS ──────────────────────────────────────────────────────────────────────
var origenesPermitidos = builder.Configuration["Cors:AllowedOrigins"]?
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    ?? [];

builder.Services.AddCors(options =>
{
    options.AddPolicy("PoliticaCors", policy =>
    {
        if (origenesPermitidos.Length > 0)
            policy.WithOrigins(origenesPermitidos)
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        else
            policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
    });
});

// ── CONTROLLERS ───────────────────────────────────────────────────────────────
builder.Services.AddControllers();

// ── OPENAPI / SWAGGER ─────────────────────────────────────────────────────────
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, _) =>
    {
        document.Info.Title       = "TW Intranet API";
        document.Info.Version     = "v1";
        document.Info.Description = "API interna de Total Weight — Intranet";
        return Task.CompletedTask;
    });
});

// ── CONFIGURACIÓN BD + JWT (disponible para inyección en adaptadores) ─────────
var cfg = builder.Configuration;

var cadenaConexion =
    $"Server={cfg["Database:Host"]};" +
    $"Port={cfg["Database:Port"]};" +
    $"Database={cfg["Database:Name"]};" +
    $"User={cfg["Database:User"]};" +
    $"Password={cfg["Database:Password"]};" +
    "AllowPublicKeyRetrieval=true;SslMode=None;";

var configuracionJwt = new ConfiguracionJwt(
    Secret:          cfg["Jwt:Secret"] ?? throw new InvalidOperationException("Jwt:Secret no configurado."),
    ExpirationHours: int.Parse(cfg["Jwt:ExpirationHours"] ?? "8"),
    Issuer:          cfg["Jwt:Issuer"]   ?? "TW.Intranet",
    Audience:        cfg["Jwt:Audience"] ?? "TW.Intranet.Clients");

builder.Services.AddSingleton(new CadenaConexionBd(cadenaConexion));
builder.Services.AddSingleton(configuracionJwt);

// ── AUTENTICACIÓN JWT ─────────────────────────────────────────────────────────
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer              = configuracionJwt.Issuer,
            ValidAudience            = configuracionJwt.Audience,
            IssuerSigningKey         = new SymmetricSecurityKey(
                                           Encoding.UTF8.GetBytes(configuracionJwt.Secret)),
            ClockSkew                = TimeSpan.Zero,
        };
    });

builder.Services.AddAuthorization();

// ── INYECCIÓN DE DEPENDENCIAS (Puertos → Adaptadores) ────────────────────────
builder.Services.AddScoped<IAutenticacionRepositorio, AutenticacionRepositorio>();
builder.Services.AddScoped<IJwtServicio,              JwtServicio>();
builder.Services.AddScoped<IVerificadorContrasena,    BcryptVerificadorContrasena>();

// Casos de uso — Autenticación
builder.Services.AddScoped<IniciarSesionCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Dashboard ─────────────────────────────────────
builder.Services.AddScoped<IDashboardRepositorio,       DashboardRepositorio>();
builder.Services.AddScoped<INotificacionesRepositorio,  NotificacionesRepositorio>();

// Casos de uso — Dashboard
builder.Services.AddScoped<ObtenerResumenDashboardCasoDeUso>();
builder.Services.AddScoped<ObtenerAlertasOperativasCasoDeUso>();
builder.Services.AddScoped<ObtenerNotificacionesCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Maestros ──────────────────────────────────────
builder.Services.AddScoped<IMaestrosRepositorio, MaestrosRepositorio>();

// Casos de uso — Maestros: Clientes
builder.Services.AddScoped<ObtenerClientesCasoDeUso>();
builder.Services.AddScoped<ObtenerClientePorIdCasoDeUso>();
builder.Services.AddScoped<GuardarClienteCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoClienteCasoDeUso>();

// Casos de uso — Maestros: Catálogos
builder.Services.AddScoped<ObtenerCatalogoCasoDeUso>();

// Casos de uso — Maestros: Sedes
builder.Services.AddScoped<ObtenerSedesPorClienteCasoDeUso>();
builder.Services.AddScoped<GuardarSedeCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoSedeCasoDeUso>();

// Casos de uso — Maestros: Contactos
builder.Services.AddScoped<ObtenerContactosPorClienteCasoDeUso>();
builder.Services.AddScoped<GuardarContactoCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoContactoCasoDeUso>();

// ─────────────────────────────────────────────────────────────────────────────
var app = builder.Build();

if (!app.Environment.IsProduction())
{
    app.MapOpenApi();
    app.MapScalarApiReference(options =>
    {
        options.Title = "TW Intranet API";
        options.Theme = ScalarTheme.DeepSpace;
    });
}

app.UseHttpsRedirection();
app.UseCors("PoliticaCors");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
