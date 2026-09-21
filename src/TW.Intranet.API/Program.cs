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

// ── OPENAPI ───────────────────────────────────────────────────────────────────
builder.Services.AddOpenApi();

// ── CADENA DE CONEXIÓN (disponible para inyección en adaptadores) ──────────────
var cfg = builder.Configuration;
var cadenaConexion =
    $"Server={cfg["Database:Host"]};" +
    $"Port={cfg["Database:Port"]};" +
    $"Database={cfg["Database:Name"]};" +
    $"User={cfg["Database:User"]};" +
    $"Password={cfg["Database:Password"]};" +
    "AllowPublicKeyRetrieval=true;SslMode=None;";

builder.Services.AddSingleton(new CadenaConexionBd(cadenaConexion));

// ─────────────────────────────────────────────────────────────────────────────
var app = builder.Build();

if (app.Environment.IsDevelopment())
    app.MapOpenApi();

app.UseHttpsRedirection();
app.UseCors("PoliticaCors");
app.MapControllers();

app.Run();

// Registro simple que los adaptadores de infraestructura reciben por DI
public record CadenaConexionBd(string Valor);
