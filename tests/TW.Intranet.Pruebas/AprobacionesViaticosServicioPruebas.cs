using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Pruebas;

/// <summary>HU-52 / HU-57: validación de entrada de las aprobaciones y los viáticos de la OS (intranet). Lo inválido no llega al repositorio.</summary>
public class AprobacionesViaticosServicioPruebas
{
    private static ResolverAprobacionServicioDto Decision(bool? aprobar, string? comentario) => new() { Aprobar = aprobar, Comentario = comentario };

    [Theory]
    [InlineData(0, "salida", 5)]
    [InlineData(10, "otro", 5)]
    [InlineData(10, "evidencia", 0)]
    public async Task Resolver_rechaza_os_tipo_o_id_invalidos(long idOs, string tipo, long id)
    {
        var repo = new AprobacionesViaticosRepoFalso();
        var r = await new ResolverAprobacionServicioRutaCasoDeUso(repo).EjecutarAsync(1, idOs, tipo, id, Decision(true, "Conforme"));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Resolver_exige_comentario()
    {
        var repo = new AprobacionesViaticosRepoFalso();
        var r = await new ResolverAprobacionServicioRutaCasoDeUso(repo).EjecutarAsync(1, 10, "ensayo", 5, Decision(false, "   "));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Resolver_rechaza_comentario_de_mas_de_500()
    {
        var repo = new AprobacionesViaticosRepoFalso();
        var r = await new ResolverAprobacionServicioRutaCasoDeUso(repo).EjecutarAsync(1, 10, "salida", 5, Decision(true, new string('a', 501)));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Resolver_exige_decidir_aprobar_o_rechazar()
    {
        var repo = new AprobacionesViaticosRepoFalso();
        var r = await new ResolverAprobacionServicioRutaCasoDeUso(repo).EjecutarAsync(1, 10, "llegada", 5, Decision(null, "ok"));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Resolver_valido_llega_al_repositorio_con_tipo_normalizado()
    {
        var repo = new AprobacionesViaticosRepoFalso();
        var r = await new ResolverAprobacionServicioRutaCasoDeUso(repo).EjecutarAsync(1, 10, " SALIDA ", 5, Decision(true, "Condición: EPP completo"));
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(1, repo.Llamadas);
    }

    [Theory]
    [InlineData("borrar", "x")]
    [InlineData("observar", "")]
    [InlineData("rechazar", "no")]
    public async Task RevisarGasto_valida_accion_y_comentario(string accion, string comentario)
    {
        var repo = new AprobacionesViaticosRepoFalso();
        var r = await new RevisarGastoServicioRutaCasoDeUso(repo).EjecutarAsync(1, 10, 20, new RevisarGastoDto { Accion = accion, Comentario = comentario });
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(6)]
    public async Task Comprobante_n_fuera_de_rango(int n)
    {
        var repo = new AprobacionesViaticosRepoFalso { RutaComprobante = "gastos/1/a.jpg" };
        var r = await new ObtenerComprobanteGastoServicioRutaCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(1, 10, 20, n);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Comprobante_de_otra_os_se_bloquea()
    {
        // El SP responde 1 cuando el gasto no es de esa OS (anti-IDOR); el caso de uso no abre ningún archivo
        var repo = new AprobacionesViaticosRepoFalso { RutaComprobante = null };
        var r = await new ObtenerComprobanteGastoServicioRutaCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(1, 10, 99, 1);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Null(r.Datos);
    }

    [Theory]
    [InlineData("https://otro-sitio.com/boleta.jpg")]
    [InlineData("../../etc/passwd.jpg")]
    [InlineData("gastos/1/script.html")]
    public async Task Comprobante_no_sirve_enlaces_externos_rutas_con_puntos_ni_otros_tipos(string ruta)
    {
        var repo = new AprobacionesViaticosRepoFalso { RutaComprobante = ruta };
        var r = await new ObtenerComprobanteGastoServicioRutaCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(1, 10, 20, 1);
        Assert.Equal(1, r.IdTipoMensaje);
    }

    [Fact]
    public async Task Comprobante_valido_se_abre()
    {
        var almacen = new AlmacenFalso();
        almacen.Archivos["gastos/1/a.jpg"] = [0xFF, 0xD8, 0xFF, 0x01];
        var repo = new AprobacionesViaticosRepoFalso { RutaComprobante = "gastos/1/a.jpg" };
        var r = await new ObtenerComprobanteGastoServicioRutaCasoDeUso(repo, almacen).EjecutarAsync(1, 10, 20, 1);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal("image/jpeg", r.Datos!.TipoContenido);
    }
}
