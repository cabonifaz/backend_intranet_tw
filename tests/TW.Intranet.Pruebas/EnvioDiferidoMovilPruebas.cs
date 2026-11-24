using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Logging.Abstractions;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

internal sealed class EnvioDiferidoRepoFalso : IEnvioDiferidoMovilRepositorio
{
    public List<(long Usuario, string Metodo, string Ruta, long? Os, long? Equipo, DateTime Captura, string? Motivo, int Intentos)> Registros { get; } = [];
    public bool Falla { get; set; }

    public Task<RespuestaDto<object>> RegistrarAsync(long idUsuario, string metodo, string ruta, long? idOs, long? idOsEquipo, DateTime capturadoUtc, string? motivo, int intentos, CancellationToken ct)
    {
        if (Falla) throw new InvalidOperationException("BD caída");
        Registros.Add((idUsuario, metodo, ruta, idOs, idOsEquipo, capturadoUtc, motivo, intentos));
        return Task.FromResult(new RespuestaDto<object>(2, "Envío registrado."));
    }

    public Task<RespuestaDto<IReadOnlyList<EnvioDiferidoDto>>> ListarAsync(long idOs, long? idOsEquipo, CancellationToken ct) =>
        Task.FromResult(new RespuestaDto<IReadOnlyList<EnvioDiferidoDto>>(2, "Éxito.", []));
}

/// <summary>App móvil sin señal — constancia de envíos tardíos: lectura de las cabeceras y filtro de la API.</summary>
public class EnvioDiferidoMovilPruebas
{
    [Theory]
    [InlineData("2026-11-24T14:05:00Z", true, 14)]
    [InlineData("2026-11-24T09:05:00-05:00", true, 14)]
    [InlineData("2026-11-24T14:05:00", true, 14)] // sin zona se toma como UTC
    [InlineData("", false, 0)]
    [InlineData("no es una fecha", false, 0)]
    public void Captura_se_lee_en_utc(string valor, bool esperado, int hora)
    {
        Assert.Equal(esperado, ReglasEnvioDiferido.TryLeerCaptura(valor, out var utc));
        if (esperado) Assert.Equal(hora, utc.Hour);
    }

    [Theory]
    [InlineData("3", 3)]
    [InlineData("500", 99)]
    [InlineData("-4", 0)]
    [InlineData("abc", 0)]
    [InlineData(null, 0)]
    public void Intentos_quedan_entre_0_y_99(string? valor, int esperado) => Assert.Equal(esperado, ReglasEnvioDiferido.LeerIntentos(valor));

    [Theory]
    [InlineData("POST", true)]
    [InlineData("put", true)]
    [InlineData("DELETE", true)]
    [InlineData("GET", false)]
    public void Solo_las_escrituras_dejan_constancia(string metodo, bool esperado) => Assert.Equal(esperado, ReglasEnvioDiferido.EsEscritura(metodo));

    private static async Task<(EnvioDiferidoRepoFalso Repo, bool Siguio)> Ejecutar(
        string metodo, string ruta, Action<HttpRequest>? cabeceras, object? resultado, long idUsuario = 77, bool conUsuario = true, EnvioDiferidoRepoFalso? repo = null)
    {
        repo ??= new EnvioDiferidoRepoFalso();
        var http = new DefaultHttpContext();
        http.Request.Method = metodo;
        http.Request.Path = ruta;
        if (conUsuario) http.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, idUsuario.ToString())], "test"));
        cabeceras?.Invoke(http.Request);

        var rutaValores = new RouteData();
        rutaValores.Values["idOs"] = "15";
        rutaValores.Values["idOsEquipo"] = "40";
        var accion = new ActionContext(http, rutaValores, new ActionDescriptor());
        var ejecutando = new ActionExecutingContext(accion, [], new Dictionary<string, object?>(), new object());
        var filtro = new EnvioDiferidoMovilFilter(new RegistrarEnvioDiferidoMovilCasoDeUso(repo), NullLogger<EnvioDiferidoMovilFilter>.Instance);

        var siguio = false;
        await filtro.OnActionExecutionAsync(ejecutando, () =>
        {
            siguio = true;
            return Task.FromResult(new ActionExecutedContext(accion, [], new object()) { Result = resultado is null ? null : new ObjectResult(resultado) });
        });
        return (repo, siguio);
    }

    private static Action<HttpRequest> Con(string captura, string? motivo = "sin_senal", string? intentos = "2") => r =>
    {
        r.Headers[ReglasEnvioDiferido.CabeceraCapturadoEn] = captura;
        if (motivo is not null) r.Headers[ReglasEnvioDiferido.CabeceraMotivo] = motivo;
        if (intentos is not null) r.Headers[ReglasEnvioDiferido.CabeceraIntentos] = intentos;
    };

    private static RespuestaDto<object> Exito => new(2, "Éxito.");

    [Fact]
    public async Task Un_reenvio_aceptado_deja_constancia_con_servicio_equipo_motivo_e_intentos()
    {
        var (repo, siguio) = await Ejecutar("PUT", "/api/movil/servicios/15/equipos/40/ensayos", Con("2026-11-24T14:05:00Z"), Exito);
        Assert.True(siguio);
        var r = Assert.Single(repo.Registros);
        Assert.Equal((77L, "PUT", "/api/movil/servicios/15/equipos/40/ensayos", (long?)15, (long?)40, "sin_senal", 2), (r.Usuario, r.Metodo, r.Ruta, r.Os, r.Equipo, r.Motivo, r.Intentos));
        Assert.Equal(new DateTime(2026, 11, 24, 14, 5, 0), r.Captura);
    }

    [Fact]
    public async Task Sin_la_cabecera_de_captura_no_deja_constancia() =>
        Assert.Empty((await Ejecutar("PUT", "/api/movil/servicios/15/equipos/40/ensayos", null, Exito)).Repo.Registros);

    [Fact]
    public async Task Una_consulta_GET_no_deja_constancia() =>
        Assert.Empty((await Ejecutar("GET", "/api/movil/servicios/15/equipos/40/ensayos", Con("2026-11-24T14:05:00Z"), Exito)).Repo.Registros);

    [Fact]
    public async Task Fuera_de_api_movil_no_deja_constancia() =>
        Assert.Empty((await Ejecutar("POST", "/api/servicios/15/algo", Con("2026-11-24T14:05:00Z"), Exito)).Repo.Registros);

    [Theory]
    [InlineData(1)]
    [InlineData(3)]
    public async Task Una_escritura_rechazada_no_deja_constancia(int tipo) =>
        Assert.Empty((await Ejecutar("POST", "/api/movil/servicios/15/llegada", Con("2026-11-24T14:05:00Z"), new RespuestaDto<object>(tipo, "No."))).Repo.Registros);

    [Fact]
    public async Task Sin_sesion_no_deja_constancia() =>
        Assert.Empty((await Ejecutar("POST", "/api/movil/servicios/15/llegada", Con("2026-11-24T14:05:00Z"), Exito, conUsuario: false)).Repo.Registros);

    [Fact]
    public async Task Un_fallo_al_guardar_la_constancia_no_rompe_la_respuesta()
    {
        var repo = new EnvioDiferidoRepoFalso { Falla = true };
        var (_, siguio) = await Ejecutar("POST", "/api/movil/servicios/15/llegada", Con("2026-11-24T14:05:00Z"), Exito, repo: repo);
        Assert.True(siguio);
    }
}
