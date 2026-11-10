using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using QuestPDF.Infrastructure;
using Scalar.AspNetCore;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Adaptadores;
using TW.Intranet.Infraestructura.Configuracion;

// QuestPDF: licencia Community (gratuita hasta USD 1M revenue/año).
QuestPDF.Settings.License = LicenseType.Community;
// Permite usar fuentes del sistema (Helvetica, Arial, etc.). Sin esto, QuestPDF 2026.9+
// solo acepta la fuente embebida "Lato" y falla con "font not available".
QuestPDF.Settings.UseEnvironmentFonts = true;

var builder = WebApplication.CreateBuilder(args);

// Desarrollo seguro (HU-52, hallazgo de las pruebas de Ethical Hacking): no revelar la tecnología del servidor en la cabecera "Server".
builder.WebHost.ConfigureKestrel(opciones => opciones.AddServerHeader = false);

// Carga appsettings.Local.json si existe (para desarrollo local, no se sube a git)
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);

// ── CORS ──────────────────────────────────────────────────────────────────────
// Orígenes EXPLÍCITOS (Cors__AllowedOrigins, separados por coma) con AllowCredentials: lo exige el cliente de SignalR.
// Cada origen debe ser http(s)://dominio[:puerto], sin ruta; se ignora la "/" final. Los inválidos se descartan (advertencia en el log).
// Si no hay ninguno válido, la API arranca igual pero NO permite orígenes cruzados (advertencia en el log). Nunca AllowAnyOrigin.
var origenesInvalidos = new List<string>();
var origenesPermitidos = (builder.Configuration["Cors:AllowedOrigins"] ?? "")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    .Select(o =>
    {
        if (Uri.TryCreate(o.TrimEnd('/'), UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)
            && uri.AbsolutePath == "/" && string.IsNullOrEmpty(uri.Query))
            return uri.GetLeftPart(UriPartial.Authority);
        origenesInvalidos.Add(o);
        return null;
    })
    .OfType<string>()
    .Distinct(StringComparer.OrdinalIgnoreCase)
    .ToArray();

builder.Services.AddCors(options =>
{
    options.AddPolicy("PoliticaCors", policy =>
    {
        if (origenesPermitidos.Length > 0)
            policy.WithOrigins(origenesPermitidos)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        else
            policy.SetIsOriginAllowed(_ => false);
    });
});

// ── CONTROLLERS ───────────────────────────────────────────────────────────────
// Permisos por rol + área en cada endpoint marcado con [RequierePermiso] (#4301).
// Se apaga con la variable de entorno Permisos__ValidarEnBack=false.
builder.Services.AddMemoryCache();
builder.Services.AddScoped<TW.Intranet.API.Seguridad.PermisosFilter>();
builder.Services.AddControllers(o => o.Filters.AddService<TW.Intranet.API.Seguridad.PermisosFilter>())
    // Fechas en hora de Lima (UTC-5): ver Configuracion/ZonaHorariaLima.cs
    .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new TW.Intranet.API.Configuracion.FechaHoraLimaJsonConverter()));

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

// ── ALMACENAMIENTO DE ARCHIVOS (PDF de procedimientos, adjuntos) ──────────────
// Railway: volumen persistente montado en /data y variable Almacenamiento__RutaBase=/data/archivos.
// Local: si no se configura, carpeta "almacenamiento" junto a la API (ignorada por git).
var rutaAlmacenamientoConfigurada = cfg["Almacenamiento:RutaBase"];
var configuracionAlmacenamiento = new ConfiguracionAlmacenamiento(
    string.IsNullOrWhiteSpace(rutaAlmacenamientoConfigurada)
        ? Path.Combine(builder.Environment.ContentRootPath, "almacenamiento")
        : rutaAlmacenamientoConfigurada);
builder.Services.AddSingleton(configuracionAlmacenamiento);
builder.Services.AddSingleton<IAlmacenArchivos, AlmacenArchivosLocal>();

// ── AUTENTICACIÓN JWT ─────────────────────────────────────────────────────────
const string MotivoSesionMovilItem = "motivo_sesion_movil";
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
            // HU-90 parte 2: por WebSocket el navegador no puede mandar la cabecera Authorization, así que el cliente de SignalR
            // envía el JWT en la query (access_token). Se acepta SOLO en la ruta del hub; en cualquier otra ruta se ignora.
            // La query no se escribe en ningún log (ver Logging en appsettings.json).
            OnMessageReceived = context =>
            {
                if (string.IsNullOrEmpty(context.Token)
                    && context.HttpContext.Request.Path.StartsWithSegments(TW.Intranet.API.TiempoReal.NotificacionesHub.Ruta, StringComparison.OrdinalIgnoreCase))
                {
                    var tokenQuery = context.Request.Query["access_token"].ToString();
                    if (!string.IsNullOrEmpty(tokenQuery))
                        context.Token = tokenQuery;
                }
                return Task.CompletedTask;
            },

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

                // App móvil (App Mobile HU-01): su sesión vive en sesion_usuario (1 equipo a la vez)
                // y es independiente de la sesión de la intranet (usuario.sesion_token).
                var canalClaim = claims?.FirstOrDefault(c => c.Type == "canal");
                var rutaPedida = context.HttpContext.Request.Path;
                bool esValido;
                if (canalClaim?.Value == "movil")
                {
                    // Desarrollo seguro: el token de la app solo sirve en las rutas que usa la app.
                    if (!TW.Intranet.API.Seguridad.SeguridadAppMovil.EsRutaPermitidaTokenMovil(rutaPedida))
                    {
                        context.Fail("El token de la app no tiene acceso a este recurso.");
                        return;
                    }
                    var repositorioMovil = context.HttpContext.RequestServices
                        .GetRequiredService<IAutenticacionMovilRepositorio>();
                    var verificacion = await repositorioMovil.VerificarSesionAsync(
                        idUsuario, tokenClaim.Value, context.HttpContext.RequestAborted);
                    esValido = verificacion.IdTipoMensaje == 2;
                    if (!esValido)
                        // El 401 lleva el motivo (p. ej. "se inició sesión con tu usuario en otro equipo") para que la app lo muestre.
                        // Si falló la BD (IdTipoMensaje 3) no se expone su detalle.
                        context.HttpContext.Items[MotivoSesionMovilItem] = verificacion.IdTipoMensaje == 1 && !string.IsNullOrWhiteSpace(verificacion.Mensaje)
                            ? verificacion.Mensaje
                            : "Tu sesión terminó. Vuelve a iniciar sesión.";
                }
                else if (TW.Intranet.API.Seguridad.SeguridadAppMovil.EsRutaApp(rutaPedida))
                {
                    // Un token de la intranet no se usa en api/movil/* (la intranet nunca llama a esas rutas).
                    context.Fail("Este recurso es solo para la app móvil.");
                    return;
                }
                else
                {
                    var repositorio = context.HttpContext.RequestServices
                        .GetRequiredService<IAutenticacionRepositorio>();
                    esValido = await repositorio.VerificarSesionTokenAsync(
                        idUsuario, tokenClaim.Value, context.HttpContext.RequestAborted);
                }

                if (!esValido)
                    context.Fail("Sesión invalidada. Por favor inicia sesión nuevamente.");
            },

            // 401 de un token de la app con sesión cerrada: cuerpo con el sobre estándar y el motivo.
            // Los demás 401 (intranet, firma inválida, JWT vencido) siguen igual que antes.
            OnChallenge = async context =>
            {
                if (context.HttpContext.Items.TryGetValue(MotivoSesionMovilItem, out var motivo) && motivo is string mensaje)
                {
                    context.HandleResponse();
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    context.Response.Headers.WWWAuthenticate = "Bearer";
                    await context.Response.WriteAsJsonAsync(new { idTipoMensaje = 1, mensaje });
                }
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
builder.Services.AddScoped<ObtenerMisDatosCasoDeUso>();

// ── APP MÓVIL DE CAMPO — acceso con usuario y 1 equipo a la vez (App Mobile HU-01) ──
// Variables (opcionales): AppMovil__HorasExpiracion (12), AppMovil__ReemplazarSesionAnterior (true).
//   true (por defecto) = sesión única: el nuevo equipo cierra la sesión del anterior; el primer equipo recibe 401 con el motivo.
//   false = si el usuario ya tiene sesión en otro equipo, el nuevo ingreso se rechaza.
builder.Services.AddSingleton(new TW.Intranet.Aplicacion.Dtos.OpcionesSesionMovil(
    HorasExpiracion:          int.TryParse(cfg["AppMovil:HorasExpiracion"], out var horasSesionMovil) ? horasSesionMovil : 12,
    ReemplazarSesionAnterior: !bool.TryParse(cfg["AppMovil:ReemplazarSesionAnterior"], out var reemplazarSesionMovil) || reemplazarSesionMovil));
// Desarrollo seguro (opcionales): AppMovil__MaxIntentosFallidos (5), AppMovil__MinutosBloqueo (15),
// AppMovil__IngresosPorMinutoPorIp (10). Solo afectan al ingreso de la app, no al de la intranet.
var opcionesSeguridadMovil = new TW.Intranet.Aplicacion.Dtos.OpcionesSeguridadMovil(
    MaxIntentosFallidos:    int.TryParse(cfg["AppMovil:MaxIntentosFallidos"], out var maxIntentosMovil) ? maxIntentosMovil : 5,
    MinutosBloqueo:         int.TryParse(cfg["AppMovil:MinutosBloqueo"], out var minutosBloqueoMovil) ? minutosBloqueoMovil : 15,
    IngresosPorMinutoPorIp: int.TryParse(cfg["AppMovil:IngresosPorMinutoPorIp"], out var ingresosIpMovil) ? ingresosIpMovil : 10);
builder.Services.AddSingleton(opcionesSeguridadMovil);
builder.Services.AddSingleton<IControlIntentosIngreso, ControlIntentosIngresoMemoria>();
TW.Intranet.API.Seguridad.SeguridadAppMovil.AgregarSeguridadAppMovil(builder.Services, opcionesSeguridadMovil);
builder.Services.AddScoped<IAutenticacionMovilRepositorio, AutenticacionMovilRepositorio>();
builder.Services.AddScoped<IniciarSesionMovilCasoDeUso>();
builder.Services.AddScoped<CerrarSesionMovilCasoDeUso>();
builder.Services.AddScoped<LiberarSesionMovilCasoDeUso>();
builder.Services.AddScoped<AsignarAccesoMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerAccesoMovilCasoDeUso>();
// App Mobile HU-02 — menú principal
builder.Services.AddScoped<IMenuMovilRepositorio, MenuMovilRepositorio>();
builder.Services.AddScoped<ObtenerResumenMenuMovilCasoDeUso>();
// App Mobile HU-03 — agenda de servicios programados
builder.Services.AddScoped<IServiciosMovilRepositorio, ServiciosMovilRepositorio>();
builder.Services.AddScoped<ObtenerServiciosProgramadosMovilCasoDeUso>();
// App Mobile HU-02 / HU-04 — notificaciones del usuario
builder.Services.AddScoped<INotificacionesMovilRepositorio, NotificacionesMovilRepositorio>();
builder.Services.AddScoped<ObtenerNotificacionesMovilCasoDeUso>();
builder.Services.AddScoped<MarcarNotificacionMovilCasoDeUso>();
// App Mobile HU-05 — registro de demoras en ruta
builder.Services.AddScoped<IDemorasMovilRepositorio, DemorasMovilRepositorio>();
builder.Services.AddScoped<ObtenerDemorasMovilCasoDeUso>();
builder.Services.AddScoped<RegistrarDemoraMovilCasoDeUso>();
// App Mobile HU-06 — registro de llegada y Hard Stop
builder.Services.AddScoped<ILlegadaMovilRepositorio, LlegadaMovilRepositorio>();
builder.Services.AddScoped<ObtenerLlegadaMovilCasoDeUso>();
builder.Services.AddScoped<ValidarLlegadaMovilCasoDeUso>();
builder.Services.AddScoped<RegistrarLlegadaMovilCasoDeUso>();
// App Mobile HU-07 — lista de objetivos y selección de equipos
builder.Services.AddScoped<IObjetivosMovilRepositorio, ObjetivosMovilRepositorio>();
builder.Services.AddScoped<ObtenerObjetivosMovilCasoDeUso>();
builder.Services.AddScoped<BuscarEquipoQrMovilCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoEquipoMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerOpcionesEquipoNuevoMovilCasoDeUso>();
builder.Services.AddScoped<RegistrarEquipoNuevoMovilCasoDeUso>();
// App Mobile HU-08 / HU-09 — trabajo en el equipo y variables ambientales
builder.Services.AddScoped<ITrabajoEquipoMovilRepositorio, TrabajoEquipoMovilRepositorio>();
builder.Services.AddScoped<ObtenerTrabajoEquipoMovilCasoDeUso>();
builder.Services.AddScoped<GuardarVariablesAmbientalesMovilCasoDeUso>();
// App Mobile HU-10 — ensayos y calibración (pesaje y excentricidad)
builder.Services.AddScoped<IEnsayosMovilRepositorio, EnsayosMovilRepositorio>();
builder.Services.AddScoped<ObtenerEnsayosMovilCasoDeUso>();
builder.Services.AddScoped<GuardarEnsayosMovilCasoDeUso>();
builder.Services.AddScoped<RegistrarLlamadaEnsayoMovilCasoDeUso>();
// App Mobile HU-11 / HU-12 / HU-13 — registro fotográfico con validación IA, evidencia forzada y microvideo de encendido
builder.Services.AddScoped<IEvidenciasMovilRepositorio, EvidenciasMovilRepositorio>();
builder.Services.AddScoped<ObtenerEvidenciasMovilCasoDeUso>();
builder.Services.AddScoped<RegistrarEvidenciaMovilCasoDeUso>();
builder.Services.AddScoped<ForzarEvidenciaMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerArchivoEvidenciaMovilCasoDeUso>();
// App Mobile HU-19 — Asistente IA y Procedimientos (la IA y la lectura de los PDF oficiales se registran más abajo, junto a Gemini)
builder.Services.AddScoped<IAsistenteMovilRepositorio, AsistenteMovilRepositorio>();
builder.Services.AddScoped<ObtenerInicioAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerEquiposAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ConsultarAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerConsultaAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ValorarConsultaAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerFuenteAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<TranscribirVozAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ListarGuardadosAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<GuardarAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerGuardadoAsistenteMovilCasoDeUso>();
builder.Services.AddScoped<EliminarGuardadoAsistenteMovilCasoDeUso>();
// App Mobile HU-28 / HU-31 — menú de Jefatura y centro de aprobaciones
builder.Services.AddScoped<ObtenerMenuJefaturaMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerAprobacionesMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerAprobacionSalidaMovilCasoDeUso>();
builder.Services.AddScoped<ResolverAprobacionSalidaMovilCasoDeUso>();
// App Mobile HU-25 / HU-26 — viáticos asignados al programar y gastos rendidos
builder.Services.AddScoped<IViaticosMovilRepositorio, ViaticosMovilRepositorio>();
builder.Services.AddScoped<ObtenerViaticosMovilCasoDeUso>();
// App Mobile HU-04 — detalle del servicio y checklist de pre-salida
builder.Services.AddScoped<IPresalidaMovilRepositorio, PresalidaMovilRepositorio>();
builder.Services.AddScoped<ObtenerDetalleServicioMovilCasoDeUso>();
builder.Services.AddScoped<ObtenerChecklistSalidaMovilCasoDeUso>();
builder.Services.AddScoped<MarcarItemChecklistSalidaMovilCasoDeUso>();
builder.Services.AddScoped<SolicitarAutorizacionSalidaMovilCasoDeUso>();
builder.Services.AddScoped<IniciarTrasladoMovilCasoDeUso>();
// App Mobile HU-04 — visto bueno de salida desde la intranet (encargado de Servicio Técnico / Metrología)
builder.Services.AddScoped<IAutorizacionSalidaRepositorio, AutorizacionSalidaRepositorio>();
builder.Services.AddScoped<ObtenerAutorizacionesSalidaCasoDeUso>();
builder.Services.AddScoped<ResolverAutorizacionSalidaCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Dashboard ─────────────────────────────────────
builder.Services.AddScoped<IDashboardRepositorio,       DashboardRepositorio>();
builder.Services.AddScoped<INotificacionesRepositorio,  NotificacionesRepositorio>();

// Casos de uso — Dashboard
builder.Services.AddScoped<ObtenerResumenDashboardCasoDeUso>();
builder.Services.AddScoped<ObtenerAlertasOperativasCasoDeUso>();
builder.Services.AddScoped<ObtenerNotificacionesCasoDeUso>();

// Casos de uso — HU-90 Centro de Notificaciones (campana + bandeja /notificaciones)
builder.Services.AddScoped<ObtenerResumenNotificacionesCasoDeUso>();
builder.Services.AddScoped<ObtenerBandejaNotificacionesCasoDeUso>();
builder.Services.AddScoped<ObtenerDetalleNotificacionCasoDeUso>();
builder.Services.AddScoped<MarcarNotificacionesLeidasCasoDeUso>();
builder.Services.AddScoped<ArchivarNotificacionCasoDeUso>();
builder.Services.AddScoped<ObtenerFiltrosNotificacionesCasoDeUso>();
builder.Services.AddScoped<GenerarAlertasOperativasCasoDeUso>();
// HU-90: alertas operativas del Módulo 11 → notificaciones (AlertasOperativas:Habilitado / IntervaloSegundos)
builder.Services.AddHostedService<TW.Intranet.API.Configuracion.AlertasOperativasWorker>();

// ── HU-90 parte 2 — Tiempo real (SignalR, hub /hubs/notificaciones) ───────────
// Una sola instancia en Railway: grupos en memoria, sin backplane. Si algún día hay varias réplicas, agregar el paquete
// Microsoft.AspNetCore.SignalR.StackExchangeRedis y la variable Redis__Conexion (.AddStackExchangeRedis(...)).
builder.Services.AddSignalR(o =>
    {
        o.EnableDetailedErrors      = false;
        o.KeepAliveInterval         = TimeSpan.FromSeconds(15);
        o.ClientTimeoutInterval     = TimeSpan.FromSeconds(30);
        o.MaximumReceiveMessageSize = 16 * 1024;   // el cliente solo envía suscripciones
    })
    .AddJsonProtocol(o => o.PayloadSerializerOptions.Converters.Add(new TW.Intranet.API.Configuracion.FechaHoraLimaJsonConverter()));
builder.Services.AddSingleton<INotificadorTiempoReal, TW.Intranet.API.TiempoReal.NotificadorSignalR>();
builder.Services.AddScoped<ObtenerNotificacionesNuevasCasoDeUso>();
// notificacion.creada sin tocar los SPs que insertan (TiempoReal:Habilitado / IntervaloSegundos)
builder.Services.AddHostedService<TW.Intranet.API.TiempoReal.NotificacionesTiempoRealWorker>();

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
builder.Services.AddScoped<IAdjuntosRequerimientoRepositorio, AdjuntosRequerimientoRepositorio>();
builder.Services.AddScoped<SubirAdjuntosRequerimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerAdjuntoRequerimientoCasoDeUso>();
builder.Services.AddScoped<EliminarAdjuntoRequerimientoCasoDeUso>();
builder.Services.AddScoped<ICarteraClientesRepositorio, CarteraClientesRepositorio>();
builder.Services.AddScoped<ObtenerCarteraClientesCasoDeUso>();
builder.Services.AddScoped<AsignarCarteraClientesCasoDeUso>();

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
builder.Services.AddScoped<ValidarNombreUsuarioCasoDeUso>();

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
builder.Services.AddScoped<ObtenerPermisoPdfProcedimientoCasoDeUso>();
builder.Services.AddScoped<SubirPdfProcedimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerPdfProcedimientoCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Catálogos editables (HU-86) ──────────────────
builder.Services.AddScoped<ICatalogosRepositorio, CatalogosRepositorio>();
builder.Services.AddScoped<AgregarItemCatalogoCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Equipos del Cliente (HU-88) ──────────────────
builder.Services.AddScoped<IEquiposClienteRepositorio, EquiposClienteRepositorio>();
builder.Services.AddScoped<ObtenerEquiposClienteCasoDeUso>();
builder.Services.AddScoped<ObtenerEquipoClientePorIdCasoDeUso>();
builder.Services.AddScoped<GuardarEquipoClienteCasoDeUso>();
builder.Services.AddScoped<CambiarEstadoEquipoClienteCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Propuestas (HU-07 / HU-08 / HU-09 / HU-10 / HU-11 / HU-12) ───────────────────
builder.Services.AddScoped<IPropuestasRepositorio, PropuestasRepositorio>();
builder.Services.AddScoped<ObtenerDatosNuevaPropuestaCasoDeUso>();
builder.Services.AddScoped<ObtenerPropuestasCasoDeUso>();
builder.Services.AddScoped<ObtenerPropuestaPorIdCasoDeUso>();
builder.Services.AddScoped<GuardarPropuestaCasoDeUso>();
builder.Services.AddScoped<ObtenerKpisPropuestasCasoDeUso>();
builder.Services.AddScoped<ObtenerDetallePropuestaCasoDeUso>();
builder.Services.AddScoped<CrearNuevaVersionPropuestaCasoDeUso>();
builder.Services.AddScoped<PrevisualizarDescuentoPropuestaCasoDeUso>();
builder.Services.AddScoped<AplicarDescuentoPropuestaCasoDeUso>();
builder.Services.AddScoped<QuitarDescuentoPropuestaCasoDeUso>();
builder.Services.AddScoped<PrevisualizarDescuentoOpcionalesCasoDeUso>();
builder.Services.AddScoped<AplicarDescuentoOpcionalesCasoDeUso>();
builder.Services.AddScoped<QuitarDescuentoOpcionalesCasoDeUso>();
builder.Services.AddScoped<PrepararVistoBuenoPropuestaCasoDeUso>();
builder.Services.AddScoped<EnviarVistoBuenoPropuestaCasoDeUso>();
builder.Services.AddScoped<PrepararAnulacionPropuestaCasoDeUso>();
builder.Services.AddScoped<AnularPropuestaCasoDeUso>();
builder.Services.AddScoped<PrepararEnvioClienteCasoDeUso>();
builder.Services.AddScoped<EnviarPropuestaClienteCasoDeUso>();
builder.Services.AddScoped<SolicitarRevocacionVbCasoDeUso>();
builder.Services.AddScoped<ResolverRevocacionVbCasoDeUso>();
builder.Services.AddScoped<IPropuestaPdfGenerador, PropuestaPdfGeneradorQuestPdf>();
builder.Services.AddScoped<IOrdenServicioPdfGenerador, OrdenServicioPdfGeneradorQuestPdf>();
builder.Services.AddScoped<GenerarPdfOrdenServicioCasoDeUso>();
builder.Services.AddScoped<GenerarPdfPropuestaCasoDeUso>();
builder.Services.AddScoped<GenerarPdfPreviewPropuestaCasoDeUso>();

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
builder.Services.AddScoped<ObtenerMisAccionesCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Directorio interno (#4303) y duplicados (#4290) ──
builder.Services.AddScoped<IDirectorioRepositorio, DirectorioRepositorio>();
builder.Services.AddScoped<ObtenerDirectorioCasoDeUso>();
builder.Services.AddScoped<ObtenerCumpleanosCasoDeUso>();
builder.Services.AddScoped<VerificarDuplicadosCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Visto bueno (HU-13 / HU-14) ──────────────────
builder.Services.AddScoped<IVistoBuenoRepositorio, VistoBuenoRepositorio>();
builder.Services.AddScoped<ObtenerBandejaVistoBuenoCasoDeUso>();
builder.Services.AddScoped<ResolverVistoBuenoCasoDeUso>();
builder.Services.AddScoped<PrepararDecisionVistoBuenoCasoDeUso>();
builder.Services.AddScoped<ObtenerCorreccionPropuestaCasoDeUso>();
builder.Services.AddScoped<ObtenerValidacionesVistoBuenoCasoDeUso>();
builder.Services.AddScoped<CompararVersionesPropuestaCasoDeUso>();
builder.Services.AddScoped<ObtenerCostoSuministroCasoDeUso>();
builder.Services.AddScoped<GuardarCostoSuministroCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Órdenes de compra (Sprint 4, HU-22 a HU-28) ──
builder.Services.AddScoped<IOrdenCompraRepositorio, OrdenCompraRepositorio>();
builder.Services.AddSingleton<IGeneradorExcel, GeneradorExcelXlsx>();
builder.Services.AddScoped<ObtenerBandejaOrdenesCompraCasoDeUso>();
builder.Services.AddScoped<ObtenerDetalleOrdenCompraCasoDeUso>();
builder.Services.AddScoped<ObtenerValidacionOrdenCompraCasoDeUso>();
builder.Services.AddScoped<ObtenerTimelineOrdenCompraCasoDeUso>();
builder.Services.AddScoped<ExportarTimelineOrdenCompraCasoDeUso>();
builder.Services.AddScoped<ObtenerPdfOrdenCompraCasoDeUso>();
builder.Services.AddScoped<PrepararOrdenCompraCasoDeUso>();
builder.Services.AddScoped<PrepararEdicionOrdenCompraCasoDeUso>();
builder.Services.AddScoped<ObtenerPropuestasDisponiblesOcCasoDeUso>();
builder.Services.AddScoped<ExtraerOrdenCompraCasoDeUso>();
builder.Services.AddScoped<CompararOrdenCompraCasoDeUso>();
builder.Services.AddScoped<RegistrarOrdenCompraCasoDeUso>();
builder.Services.AddScoped<EditarOrdenCompraCasoDeUso>();
builder.Services.AddScoped<ReemplazarDocumentoOrdenCompraCasoDeUso>();
builder.Services.AddScoped<RevalidarOrdenCompraCasoDeUso>();
builder.Services.AddScoped<AutogenerarOrdenCompraCasoDeUso>();
builder.Services.AddScoped<PrepararAnulacionOrdenCompraCasoDeUso>();
builder.Services.AddScoped<AnularOrdenCompraCasoDeUso>();

// IA de órdenes de compra y de la importación de equipos de propuestas (Google Gemini, nivel gratuito de AI Studio).
// Variables: Gemini__ApiKey, Gemini__Modelo (gemini-3.5-flash-lite), Gemini__UrlBase, Gemini__TimeoutSegundos (60), Gemini__ModeloAsistente (opcional, HU-19).
// Sin ApiKey el módulo funciona igual: la ficha se llena a mano y la validación usa solo las reglas.
var seccionGemini = cfg.GetSection("Gemini");
var configuracionGemini = new ConfiguracionGemini(
    ApiKey:          seccionGemini["ApiKey"]?.Trim() ?? "",
    Modelo:          string.IsNullOrWhiteSpace(seccionGemini["Modelo"]) ? "gemini-3.5-flash-lite" : seccionGemini["Modelo"]!.Trim(),
    UrlBase:         string.IsNullOrWhiteSpace(seccionGemini["UrlBase"]) ? "https://generativelanguage.googleapis.com/" : seccionGemini["UrlBase"]!.TrimEnd('/') + "/",
    TimeoutSegundos: int.TryParse(seccionGemini["TimeoutSegundos"], out var timeoutGemini) && timeoutGemini > 0 ? timeoutGemini : 60);
builder.Services.AddSingleton(configuracionGemini);
if (configuracionGemini.Configurado)
{
    builder.Services.AddHttpClient<IAsistenteIaOrdenCompra, GeminiAsistenteOrdenCompra>(c =>
    {
        c.BaseAddress = new Uri(configuracionGemini.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(configuracionGemini.TimeoutSegundos);
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    });
    builder.Services.AddHttpClient<IAsistenteIaEquipos, GeminiAsistenteEquipos>(c =>
    {
        c.BaseAddress = new Uri(configuracionGemini.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(configuracionGemini.TimeoutSegundos);
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    });
    // App Mobile HU-11 / HU-13: validación de las fotos del registro fotográfico
    builder.Services.AddHttpClient<IValidadorEvidenciaIa, GeminiValidadorEvidencia>(c =>
    {
        c.BaseAddress = new Uri(configuracionGemini.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(configuracionGemini.TimeoutSegundos);
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    });
    // App Mobile HU-19: Asistente IA y Procedimientos. Lee PDF y puede tardar más: mínimo 90 s. Modelo propio opcional: Gemini__ModeloAsistente.
    builder.Services.AddSingleton(new ConfiguracionAsistenteGemini(seccionGemini["ModeloAsistente"]));
    builder.Services.AddHttpClient<IAsistenteManuales, GeminiAsistenteManuales>(c =>
    {
        c.BaseAddress = new Uri(configuracionGemini.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(Math.Max(90, configuracionGemini.TimeoutSegundos));
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    });
}
else
{
    builder.Services.AddSingleton<IAsistenteIaOrdenCompra, AsistenteIaOrdenCompraNoConfigurado>();
    builder.Services.AddSingleton<IAsistenteIaEquipos, AsistenteIaEquiposNoConfigurado>();
    builder.Services.AddSingleton<IValidadorEvidenciaIa, ValidadorEvidenciaIaNoConfigurado>();
    builder.Services.AddSingleton<IAsistenteManuales, AsistenteManualesNoConfigurado>();
}

// App Mobile HU-19: lectura de los PDF oficiales (procedimientos del almacenamiento y manuales por https). El cliente de los manuales NO sigue redirecciones por su cuenta,
// no usa proxy y solo conecta a direcciones públicas ya validadas (GuardaUrlManual: anti-SSRF); la descarga se limita a 25 s y 15 MB.
builder.Services.AddHttpClient<IDocumentosAsistente, DocumentosAsistente>(c => c.Timeout = TimeSpan.FromSeconds(25))
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        AllowAutoRedirect        = false,
        UseProxy                 = false,
        ConnectTimeout           = TimeSpan.FromSeconds(10),
        PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        ConnectCallback          = GuardaUrlManual.ConectarAsync,
    });

// ── INYECCIÓN DE DEPENDENCIAS — Propuestas: importación de equipos desde Excel con IA (Sprint 4) ──
builder.Services.AddScoped<IImportacionEquiposRepositorio, ImportacionEquiposRepositorio>();
builder.Services.AddSingleton<ILectorHojaCalculo, LectorHojaCalculoXlsx>();
builder.Services.AddScoped<AnalizarImportacionEquiposCasoDeUso>();
builder.Services.AddScoped<ConfirmarImportacionEquiposCasoDeUso>();
builder.Services.AddScoped<DescargarPlantillaImportacionEquiposCasoDeUso>();
builder.Services.AddScoped<ExportarReporteImportacionEquiposCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Órdenes de Servicio / Metrología (Sprint 4, HU-40 a HU-44) ──
builder.Services.AddScoped<IOrdenServicioRepositorio, OrdenServicioRepositorio>();
builder.Services.AddScoped<ObtenerBandejaOrdenesServicioCasoDeUso>();
builder.Services.AddScoped<ExportarBandejaOrdenesServicioCasoDeUso>();
builder.Services.AddScoped<PrepararOrdenServicioCasoDeUso>();
builder.Services.AddScoped<ObtenerPropuestasDisponiblesOsCasoDeUso>();
builder.Services.AddScoped<ObtenerMotivosOrdenServicioCasoDeUso>();
builder.Services.AddScoped<GuardarOrdenServicioCasoDeUso>();
builder.Services.AddScoped<PrepararSolicitudEdicionOsCasoDeUso>();
builder.Services.AddScoped<SolicitarEdicionOsCasoDeUso>();
builder.Services.AddScoped<ResolverSolicitudEdicionOsCasoDeUso>();
builder.Services.AddScoped<PrepararAnulacionOsCasoDeUso>();
builder.Services.AddScoped<AnularOrdenServicioCasoDeUso>();
builder.Services.AddScoped<ObtenerDetalleOrdenServicioCasoDeUso>();
builder.Services.AddScoped<ObtenerTabsOrdenServicioCasoDeUso>();
builder.Services.AddScoped<BuscarEquiposOrdenServicioCasoDeUso>();
builder.Services.AddScoped<BuscarConceptosOrdenServicioCasoDeUso>();
builder.Services.AddScoped<DescargarPlantillaImportacionOsCasoDeUso>();
builder.Services.AddScoped<AnalizarImportacionOsCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Programación Operativa (Sprint 5, HU-35) ──
builder.Services.AddScoped<IProgramacionOperativaRepositorio, ProgramacionOperativaRepositorio>();
builder.Services.AddScoped<ObtenerResumenProgramacionCasoDeUso>();
builder.Services.AddScoped<ObtenerPendientesProgramacionCasoDeUso>();
builder.Services.AddScoped<ObtenerProgramadosProgramacionCasoDeUso>();
builder.Services.AddScoped<ExportarPendientesProgramacionCasoDeUso>();
builder.Services.AddScoped<ExportarProgramadosProgramacionCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Programar Servicio y Asignar Recurso (Sprint 5, HU-36) ──
builder.Services.AddScoped<IProgramacionRepositorio, ProgramacionRepositorio>();
builder.Services.AddScoped<PrepararProgramacionCasoDeUso>();
builder.Services.AddScoped<BuscarTecnicosProgramacionCasoDeUso>();
builder.Services.AddScoped<CrearProgramacionCasoDeUso>();
builder.Services.AddScoped<DerivarSsomaProgramacionCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Detalle de la Programación y confirmación con el cliente (Sprint 5, HU-37) ──
builder.Services.AddScoped<IProgramacionDetalleRepositorio, ProgramacionDetalleRepositorio>();
builder.Services.AddScoped<ObtenerDetalleProgramacionCasoDeUso>();
builder.Services.AddScoped<IProgramacionReprogramacionRepositorio, ProgramacionReprogramacionRepositorio>();
builder.Services.AddScoped<PrepararReprogramacionCasoDeUso>();
builder.Services.AddScoped<ReprogramarProgramacionCasoDeUso>();
builder.Services.AddScoped<ObtenerSolicitudReprogramacionCasoDeUso>();
builder.Services.AddScoped<ResolverSolicitudReprogramacionCasoDeUso>();
builder.Services.AddScoped<RetirarSolicitudReprogramacionCasoDeUso>();
builder.Services.AddScoped<IProgramacionConflictosRepositorio, ProgramacionConflictosRepositorio>();
builder.Services.AddScoped<ObtenerConflictosProgramacionCasoDeUso>();
builder.Services.AddScoped<ObtenerConflictoProgramacionCasoDeUso>();
builder.Services.AddScoped<ResolverConflictoProgramacionCasoDeUso>();
builder.Services.AddScoped<IProgramacionViaticosRepositorio, ProgramacionViaticosRepositorio>();
builder.Services.AddScoped<ObtenerViaticosProgramacionCasoDeUso>();
builder.Services.AddScoped<GuardarViaticosProgramacionCasoDeUso>();
builder.Services.AddScoped<RevisarGastoProgramacionCasoDeUso>();
builder.Services.AddScoped<CerrarRendicionProgramacionCasoDeUso>();
builder.Services.AddScoped<ObtenerComprobanteGastoCasoDeUso>();
builder.Services.AddScoped<ObtenerProgramacionesTecnicoDiaCasoDeUso>();
builder.Services.AddScoped<PrepararCancelacionProgramacionCasoDeUso>();
builder.Services.AddScoped<CancelarProgramacionCasoDeUso>();
builder.Services.AddScoped<ObtenerHistorialProgramacionesOsCasoDeUso>();
builder.Services.AddScoped<RegistrarRespuestaClienteCasoDeUso>();

// HU-51 Bandeja de Seguimiento Operativo (Sprint 5): solo lectura
builder.Services.AddScoped<ISeguimientoOperativoRepositorio, SeguimientoOperativoRepositorio>();
builder.Services.AddScoped<ObtenerResumenSeguimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerServiciosSeguimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerTecnicosSeguimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerIncidenciasSeguimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerFiltrosSeguimientoCasoDeUso>();
builder.Services.AddScoped<RegistrarUbicacionMovilCasoDeUso>();

// HU-52 Detalle del Servicio en Ruta (Sprint 5): solo lectura
builder.Services.AddScoped<IDetalleServicioRutaRepositorio, DetalleServicioRutaRepositorio>();
builder.Services.AddScoped<ObtenerDetalleServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerAvanceServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerSeccionEquipoServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerMapaServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerTimelineServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerIncidenciasServicioRutaCasoDeUso>();
builder.Services.AddScoped<ExportarIncidenciasServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerCierreServicioRutaCasoDeUso>();
builder.Services.AddScoped<ObtenerAuditoriaServicioRutaCasoDeUso>(); // HU-54 Auditoría post-servicio (sin este registro todo el detalle del servicio en ruta respondía 500)
builder.Services.AddScoped<ObtenerEvidenciaIncidenciaCasoDeUso>();   // HU-52 foto de evidencia de una demora/incidencia
builder.Services.AddScoped<SubirEvidenciaSeguimientoCasoDeUso>();    // HU-53 subida de la foto de evidencia del Asistente

// HU-53 Registro operativo del Asistente de Seguimiento (Sprint 5): observación, demora/incidente y cambio manual de estado
builder.Services.AddScoped<IRegistroAsistenteRepositorio, RegistroAsistenteRepositorio>();
builder.Services.AddScoped<ObtenerFormularioRegistroAsistenteCasoDeUso>();
builder.Services.AddScoped<RegistrarAsistenteServicioRutaCasoDeUso>();

// Revisión Técnica (Sprint 5, HU-56 a HU-59) y Precotizaciones Técnicas del CRM (HU-60)
builder.Services.AddScoped<IRevisionTecnicaRepositorio, RevisionTecnicaRepositorio>();
builder.Services.AddScoped<ObtenerBandejaInformesCasoDeUso>();
builder.Services.AddScoped<ExportarBandejaInformesCasoDeUso>();
builder.Services.AddScoped<ObtenerDetalleInformeCasoDeUso>();
builder.Services.AddScoped<GuardarInformeTecnicoCasoDeUso>();
builder.Services.AddScoped<GuardarPrecotizacionInformeCasoDeUso>();
builder.Services.AddScoped<PrepararRevisionInformeCasoDeUso>();
builder.Services.AddScoped<RegistrarRevisionInformeCasoDeUso>();
builder.Services.AddScoped<ObtenerHistorialInformeCasoDeUso>();
builder.Services.AddScoped<ObtenerBandejaPrecotizacionesCasoDeUso>();
builder.Services.AddScoped<ObtenerDetallePrecotizacionCasoDeUso>();
builder.Services.AddScoped<ObtenerPrecargaPrecotizacionCasoDeUso>();
builder.Services.AddScoped<ConvertirPrecotizacionCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Expediente Digital (Sprint 4, HU-29 a HU-33) ───
builder.Services.AddScoped<IExpedienteRepositorio, ExpedienteRepositorio>();
builder.Services.AddSingleton<IGeneradorPdfTabla, GeneradorPdfTablaQuestPdf>();
builder.Services.AddScoped<ObtenerBandejaExpedientesCasoDeUso>();
builder.Services.AddScoped<ExportarBandejaExpedientesCasoDeUso>();
builder.Services.AddScoped<ObtenerDetalleExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabRqExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabPropuestasExpedienteCasoDeUso>();
builder.Services.AddScoped<CompararVersionesExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabVistoBuenoExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabSeguimientoExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabOrdenesCompraExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabOrdenServicioExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabProgramacionExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabSsomaExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabEjecucionExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerTabCierreExpedienteCasoDeUso>();
builder.Services.AddScoped<ExportarExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerDocumentosExpedienteCasoDeUso>();
builder.Services.AddScoped<ExportarDocumentosExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerArchivoExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerHistorialExpedienteCasoDeUso>();
builder.Services.AddScoped<ExportarHistorialExpedienteCasoDeUso>();
builder.Services.AddScoped<PrepararReasignacionExpedienteCasoDeUso>();
builder.Services.AddScoped<ObtenerCarteraComercialExpedienteCasoDeUso>();
builder.Services.AddScoped<BuscarResponsablesExpedienteCasoDeUso>();
builder.Services.AddScoped<ReasignarResponsableExpedienteCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Seguimiento comercial (HU-17 / HU-18 / HU-19 / HU-20 / HU-21) ────────────────
builder.Services.AddScoped<ISeguimientoComercialRepositorio, SeguimientoComercialRepositorio>();
builder.Services.AddScoped<ObtenerBandejaSeguimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerDetalleSeguimientoCasoDeUso>();
builder.Services.AddScoped<PrepararRegistroSeguimientoCasoDeUso>();
builder.Services.AddScoped<RegistrarSeguimientoCasoDeUso>();
builder.Services.AddScoped<RegistrarLlamadaSeguimientoCasoDeUso>();
builder.Services.AddScoped<GuardarBorradorCorreoSeguimientoCasoDeUso>();
builder.Services.AddScoped<EnviarCorreoSeguimientoCasoDeUso>();
builder.Services.AddScoped<SubirAdjuntosSeguimientoCasoDeUso>();
builder.Services.AddScoped<ObtenerAdjuntoSeguimientoCasoDeUso>();
builder.Services.AddScoped<PrepararReprogramacionSeguimientoCasoDeUso>();
builder.Services.AddScoped<ReprogramarAccionSeguimientoCasoDeUso>();
builder.Services.AddScoped<PrepararCierreSeguimientoCasoDeUso>();
builder.Services.AddScoped<RegistrarAceptacionSeguimientoCasoDeUso>();
builder.Services.AddScoped<RegistrarRechazoSeguimientoCasoDeUso>();
builder.Services.AddScoped<ProcesarRecordatoriosSeguimientoCasoDeUso>();
// Observaciones 2026-10-15: aviso anticipado de las acciones de seguimiento (Recordatorios:Habilitado / IntervaloSegundos)
builder.Services.AddHostedService<TW.Intranet.API.Configuracion.RecordatoriosSeguimientoWorker>();

// ── INYECCIÓN DE DEPENDENCIAS — Consulta de RUC (OpenRUC + Decolecta + caché) ─
// Variables: ConsultaRuc__DiasVigenciaCache (30), ConsultaRuc__OpenRuc__Habilitado (true),
// ConsultaRuc__OpenRuc__UrlBase (https://openruc.com/), ConsultaRuc__OpenRuc__TimeoutSegundos (8).
// Decolecta (RUC 10 y respaldo de RUC 20): ConsultaRuc__Decolecta__Token (obligatorio para usarlo),
// ConsultaRuc__Decolecta__Habilitado (true), ConsultaRuc__Decolecta__UrlBase (https://api.decolecta.com/),
// ConsultaRuc__Decolecta__TimeoutSegundos (8).
// El orden de registro es el orden en que se prueban: primero OpenRUC (RUC 20, sin token) y luego Decolecta.
// Cada proveedor usa un HttpClient con nombre propio (si no, compartirían la misma configuración).
var seccionRuc = cfg.GetSection("ConsultaRuc");
builder.Services.AddSingleton(new TW.Intranet.Aplicacion.Dtos.OpcionesConsultaRuc(
    int.TryParse(seccionRuc["DiasVigenciaCache"], out var diasCacheRuc) && diasCacheRuc > 0 ? diasCacheRuc : 30));
var configuracionOpenRuc = new ConfiguracionOpenRuc(
    Habilitado:      !bool.TryParse(seccionRuc["OpenRuc:Habilitado"], out var openRucHabilitado) || openRucHabilitado,
    UrlBase:         string.IsNullOrWhiteSpace(seccionRuc["OpenRuc:UrlBase"]) ? "https://openruc.com/" : seccionRuc["OpenRuc:UrlBase"]!.TrimEnd('/') + "/",
    TimeoutSegundos: int.TryParse(seccionRuc["OpenRuc:TimeoutSegundos"], out var timeoutRuc) && timeoutRuc > 0 ? timeoutRuc : 8);
if (configuracionOpenRuc.Habilitado)
{
    builder.Services.AddHttpClient<IProveedorRuc, OpenRucProveedor>("openruc", c =>
    {
        c.BaseAddress = new Uri(configuracionOpenRuc.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(configuracionOpenRuc.TimeoutSegundos);
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
        c.DefaultRequestHeaders.UserAgent.ParseAdd("TW-Intranet/1.0");
    });
}
var configuracionDecolecta = new ConfiguracionDecolecta(
    Habilitado:      !bool.TryParse(seccionRuc["Decolecta:Habilitado"], out var decolectaHabilitado) || decolectaHabilitado,
    UrlBase:         string.IsNullOrWhiteSpace(seccionRuc["Decolecta:UrlBase"]) ? "https://api.decolecta.com/" : seccionRuc["Decolecta:UrlBase"]!.TrimEnd('/') + "/",
    Token:           seccionRuc["Decolecta:Token"]?.Trim() ?? "",
    TimeoutSegundos: int.TryParse(seccionRuc["Decolecta:TimeoutSegundos"], out var timeoutDecolecta) && timeoutDecolecta > 0 ? timeoutDecolecta : 8);
if (configuracionDecolecta.Habilitado && configuracionDecolecta.Token.Length > 0)
{
    builder.Services.AddHttpClient<IProveedorRuc, DecolectaRucProveedor>("decolecta", c =>
    {
        c.BaseAddress = new Uri(configuracionDecolecta.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(configuracionDecolecta.TimeoutSegundos);
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
        c.DefaultRequestHeaders.UserAgent.ParseAdd("TW-Intranet/1.0");
        DecolectaRucProveedor.ConfigurarToken(c, configuracionDecolecta.Token);
    });
}
builder.Services.AddScoped<IConsultaRucRepositorio, ConsultaRucRepositorio>();
builder.Services.AddScoped<ConsultarRucCasoDeUso>();
builder.Services.AddScoped<ObtenerUsoConsultaRucCasoDeUso>();

// ── INYECCIÓN DE DEPENDENCIAS — Servicio de correo (Brevo por API HTTPS) ─────
// Variables: Correo__ApiKey, Correo__Remitente, Correo__NombreRemitente, Correo__UrlIntranet.
// Sin ApiKey no se envía nada (los intentos quedan en correo_envio como "no_configurado").
var seccionCorreo = cfg.GetSection("Correo");
var configuracionCorreo = new ConfiguracionCorreo(
    Proveedor:       string.IsNullOrWhiteSpace(seccionCorreo["Proveedor"]) ? "brevo" : seccionCorreo["Proveedor"]!.Trim().ToLowerInvariant(),
    ApiKey:          seccionCorreo["ApiKey"]?.Trim() ?? "",
    Remitente:       seccionCorreo["Remitente"]?.Trim() ?? "",
    NombreRemitente: string.IsNullOrWhiteSpace(seccionCorreo["NombreRemitente"]) ? "Intranet Total Weight" : seccionCorreo["NombreRemitente"]!.Trim(),
    UrlBase:         string.IsNullOrWhiteSpace(seccionCorreo["UrlBase"]) ? "https://api.brevo.com/" : seccionCorreo["UrlBase"]!.TrimEnd('/') + "/",
    TimeoutSegundos: int.TryParse(seccionCorreo["TimeoutSegundos"], out var timeoutCorreo) && timeoutCorreo > 0 ? timeoutCorreo : 15);
builder.Services.AddSingleton(configuracionCorreo);
builder.Services.AddSingleton(new TW.Intranet.Aplicacion.Dtos.OpcionesCorreo(
    // Si no se configura, se usa el primer origen de Cors:AllowedOrigins (la URL del front).
    UrlIntranet:   !string.IsNullOrWhiteSpace(seccionCorreo["UrlIntranet"])
                       ? seccionCorreo["UrlIntranet"]!.Trim()
                       : (cfg["Cors:AllowedOrigins"] ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault() ?? "",
    NombreSistema: "Intranet Total Weight"));
if (configuracionCorreo.Configurado && configuracionCorreo.Proveedor == "brevo")
{
    builder.Services.AddHttpClient<IEnviadorCorreo, BrevoEnviadorCorreo>(c =>
    {
        c.BaseAddress = new Uri(configuracionCorreo.UrlBase);
        c.Timeout     = TimeSpan.FromSeconds(configuracionCorreo.TimeoutSegundos);
        c.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    });
}
else
{
    builder.Services.AddSingleton<IEnviadorCorreo, EnviadorCorreoNoConfigurado>();
}
builder.Services.AddScoped<ICorreoRepositorio, CorreoRepositorio>();
builder.Services.AddScoped<NotificadorCorreo>();
builder.Services.AddScoped<ReenviarCredencialesCasoDeUso>();
builder.Services.AddScoped<EnviarCorreoPruebaCasoDeUso>();

// ─────────────────────────────────────────────────────────────────────────────
var app = builder.Build();

// El contenedor debe correr en hora de Lima (ENV TZ=America/Lima en el Dockerfile).
if (TimeZoneInfo.Local.BaseUtcOffset != TW.Intranet.API.Configuracion.ZonaHorariaLima.Zona.BaseUtcOffset)
    app.Logger.LogWarning(
        "La zona horaria del servidor es {Zona} y no la de Lima (UTC-5). DateTime.Now no coincidirá con la hora de Perú. " +
        "Configure TZ=America/Lima.", TimeZoneInfo.Local.Id);
else
    app.Logger.LogInformation("Zona horaria {Zona}, hora local {Hora:yyyy-MM-dd HH:mm:ss}", TimeZoneInfo.Local.Id, DateTime.Now);

if (string.IsNullOrWhiteSpace(rutaAlmacenamientoConfigurada) && !app.Environment.IsDevelopment())
    app.Logger.LogWarning(
        "Almacenamiento:RutaBase no está configurado. Los archivos se guardan en {Ruta}, que NO persiste entre deploys. " +
        "Configure un volumen y la variable Almacenamiento__RutaBase.", configuracionAlmacenamiento.RutaBase);
else
    app.Logger.LogInformation("Almacenamiento de archivos en {Ruta}", configuracionAlmacenamiento.RutaBase);

foreach (var origenInvalido in origenesInvalidos)
    app.Logger.LogWarning("Cors:AllowedOrigins: se ignora el origen no válido \"{Origen}\" (use http(s)://dominio[:puerto] sin ruta).", origenInvalido);
if (origenesPermitidos.Length == 0)
    app.Logger.LogWarning(
        "Cors:AllowedOrigins no está configurado: NO se permite ningún origen cruzado (el front no podrá llamar a la API ni conectarse " +
        "al hub de notificaciones). Configure la variable Cors__AllowedOrigins.");
else
    app.Logger.LogInformation("CORS permitido para: {Origenes}", string.Join(", ", origenesPermitidos));

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
// App móvil — desarrollo seguro: cabeceras en api/movil/* y límite de ingresos por IP
// (solo en los endpoints marcados con [EnableRateLimiting]; la intranet no cambia).
TW.Intranet.API.Seguridad.SeguridadAppMovil.UsarCabecerasSeguridadAppMovil(app);
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
// HU-90 parte 2: solo WebSockets (el cliente usa skipNegotiation); la conexión se cierra cuando vence el JWT.
app.MapHub<TW.Intranet.API.TiempoReal.NotificacionesHub>(TW.Intranet.API.TiempoReal.NotificacionesHub.Ruta, o =>
{
    o.Transports                       = Microsoft.AspNetCore.Http.Connections.HttpTransportType.WebSockets;
    o.CloseOnAuthenticationExpiration  = true;
});

app.Run();
