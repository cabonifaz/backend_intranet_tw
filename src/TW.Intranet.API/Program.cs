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

        options.Events = new Microsoft.AspNetCore.Authentication.JwtBearer.JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                var claims      = context.Principal?.Claims;
                var subClaim    = claims?.FirstOrDefault(c => c.Type == System.Security.Claims.ClaimTypes.NameIdentifier)
                               ?? claims?.FirstOrDefault(c => c.Type == "sub");
                var tokenClaim  = claims?.FirstOrDefault(c => c.Type == "sesion_token");

                if (subClaim is null || tokenClaim is null)
                {
                    context.Fail("Token sin claims requeridos.");
                    return;
                }

                if (!long.TryParse(subClaim.Value, out var idUsuario))
                {
                    context.Fail("Claim 'sub' inválido.");
                    return;
                }

                var repositorio = context.HttpContext.RequestServices
                    .GetRequiredService<IAutenticacionRepositorio>();

                var esValido = await repositorio.VerificarSesionTokenAsync(
                    idUsuario, tokenClaim.Value, context.HttpContext.RequestAborted);

                if (!esValido)
                    context.Fail("Sesión invalidada. Por favor inicia sesión nuevamente.");
            }
        };
    });

builder.Services.AddAuthorization();

// ── INYECCIÓN DE DEPENDENCIAS (Puertos → Adaptadores) ────────────────────────
builder.Services.AddScoped<IAutenticacionRepositorio, AutenticacionRepositorio>();
builder.Services.AddScoped<IJwtServicio,              JwtServicio>();
builder.Services.AddScoped<IVerificadorContrasena,    BcryptVerificadorContrasena>();

// Casos de uso — Autenticación
builder.Services.AddScoped<IniciarSesionCasoDeUso>();
builder.Services.AddScoped<CambiarContrasenaCasoDeUso>();

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

// Casos de uso — Maestros: Categorías de cliente
builder.Services.AddScoped<ObtenerCategoriasCasoDeUso>();
builder.Services.AddScoped<GuardarCategoriaCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoCategoriaCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — CRM ──────────────────────────────────────────
builder.Services.AddScoped<ICrmRepositorio, CrmRepositorio>();
builder.Services.AddScoped<ObtenerRequerimientosCasoDeUso>();
builder.Services.AddScoped<ObtenerCatalogosRequerimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerRequerimientoPorIdCasoDeUso>();
builder.Services.AddScoped<GuardarRequerimientoCasoDeUso>();
builder.Services.AddScoped<AnularRequerimientoCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Usuarios y Suplencias (HU-82/83/84) ──────────
builder.Services.AddScoped<IUsuariosRepositorio, UsuariosRepositorio>();
builder.Services.AddScoped<IHasherContrasena,    BcryptHasherContrasena>();

// Casos de uso — Usuarios
builder.Services.AddScoped<ObtenerUsuariosCasoDeUso>();
builder.Services.AddScoped<ObtenerUsuarioPorIdCasoDeUso>();
builder.Services.AddScoped<ObtenerJefesDisponiblesCasoDeUso>();
builder.Services.AddScoped<ObtenerSedesOperativasCasoDeUso>();
builder.Services.AddScoped<GuardarUsuarioCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoUsuarioCasoDeUso>();

// Casos de uso — Suplencias
builder.Services.AddScoped<ObtenerSuplentesCasoDeUso>();
builder.Services.AddScoped<ObtenerSuplentePorIdCasoDeUso>();
builder.Services.AddScoped<ObtenerSuplenciasPorUsuarioCasoDeUso>();
builder.Services.AddScoped<GuardarSuplenteCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoSuplenteCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Textos Base (HU-85) ──────────────────────────
builder.Services.AddScoped<ITextosBaseRepositorio, TextosBaseRepositorio>();
builder.Services.AddScoped<ObtenerTextosBaseCasoDeUso>();
builder.Services.AddScoped<ObtenerTextoBasePorIdCasoDeUso>();
builder.Services.AddScoped<GuardarTextoBaseCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoTextoBaseCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Suministros (HU-86) ──────────────────────────
builder.Services.AddScoped<ISuministrosRepositorio, SuministrosRepositorio>();
builder.Services.AddScoped<ObtenerSuministrosCasoDeUso>();
builder.Services.AddScoped<ObtenerSuministroPorIdCasoDeUso>();
builder.Services.AddScoped<GuardarSuministroCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoSuministroCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Procedimientos (HU-87) ───────────────────────
builder.Services.AddScoped<IProcedimientosRepositorio, ProcedimientosRepositorio>();
builder.Services.AddScoped<ObtenerProcedimientosCasoDeUso>();
builder.Services.AddScoped<ObtenerProcedimientoPorIdCasoDeUso>();
builder.Services.AddScoped<ObtenerProcedimientosOpcionesCasoDeUso>();
builder.Services.AddScoped<GuardarProcedimientoCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoProcedimientoCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Catálogos editables (HU-86) ──────────────────
builder.Services.AddScoped<ICatalogosRepositorio, CatalogosRepositorio>();
builder.Services.AddScoped<AgregarItemCatalogoCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Equipos del Cliente (HU-88) ──────────────────
builder.Services.AddScoped<IEquiposClienteRepositorio, EquiposClienteRepositorio>();
builder.Services.AddScoped<ObtenerEquiposClienteCasoDeUso>();
builder.Services.AddScoped<ObtenerEquipoClientePorIdCasoDeUso>();
builder.Services.AddScoped<GuardarEquipoClienteCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoEquipoClienteCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Propuestas (HU-07 / HU-08 / HU-09 / HU-10) ───────────────────
builder.Services.AddScoped<IPropuestasRepositorio, PropuestasRepositorio>();
builder.Services.AddScoped<ObtenerDatosNuevaPropuestaCasoDeUso>();
builder.Services.AddScoped<ObtenerPropuestasCasoDeUso>();
builder.Services.AddScoped<ObtenerPropuestaPorIdCasoDeUso>();
builder.Services.AddScoped<GuardarPropuestaCasoDeUso>();
builder.Services.AddScoped<ObtenerKpisPropuestasCasoDeUso>();
builder.Services.AddScoped<ObtenerDetallePropuestaCasoDeUso>();
builder.Services.AddScoped<CrearNuevaVersionPropuestaCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Ubigeo, áreas del cliente y formatos (reunión 02-oct) ──
builder.Services.AddScoped<IMaestrosComplementariosRepositorio, MaestrosComplementariosRepositorio>();
builder.Services.AddScoped<ObtenerUbigeoCasoDeUso>();
builder.Services.AddScoped<ObtenerAreasClienteCasoDeUso>();
builder.Services.AddScoped<GuardarAreaClienteCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoAreaClienteCasoDeUso>();
builder.Services.AddScoped<ObtenerSiguienteCodigoCasoDeUso>();
builder.Services.AddScoped<ObtenerFormatosVentanaCasoDeUso>();
builder.Services.AddScoped<GuardarFormatoVentanaCasoDeUso>();
builder.Services.AddScoped<ObtenerRequisitosDelClienteCasoDeUso>();
builder.Services.AddScoped<SincronizarRequisitosClienteCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Roles por niveles y permisos por área (reunión 02-oct) ──
builder.Services.AddScoped<IPermisosRepositorio, PermisosRepositorio>();
builder.Services.AddScoped<ObtenerMisPermisosCasoDeUso>();
builder.Services.AddScoped<ObtenerPermisosAreaRolCasoDeUso>();
builder.Services.AddScoped<GuardarPermisoCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Directorio interno (#4303) y duplicados (#4290) ──
builder.Services.AddScoped<IDirectorioRepositorio, DirectorioRepositorio>();
builder.Services.AddScoped<ObtenerDirectorioCasoDeUso>();
builder.Services.AddScoped<ObtenerCumpleanosCasoDeUso>();
builder.Services.AddScoped<VerificarDuplicadosCasoDeUso>();

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
