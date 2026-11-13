using System.Reflection;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Mapa de la sede: ubigeo por coordenadas y ubicación al guardar la sede (rango de Perú, las dos coordenadas o ninguna).</summary>
public class UbicacionSedePruebas
{
    private static GuardarSedeDto Sede(decimal? lat, decimal? lng) =>
        new(0, 1, "Planta Ica", null, "ICA", "ICA", "ICA", null, "Panamericana Sur km 300", lat, lng);

    [Theory]
    [InlineData(-14.0640, -75.7286)]   // Ica
    [InlineData(-3.7500, -73.2500)]    // Iquitos
    [InlineData(-18.5, -68.0)]         // esquina del recuadro
    public void Ubicacion_dentro_del_peru_es_valida(double lat, double lng)
        => Assert.Null(UbicacionPeru.Validar((decimal)lat, (decimal)lng, obligatoria: true));

    [Theory]
    [InlineData(40.4168, -3.7038)]     // Madrid
    [InlineData(-12.0, -66.0)]         // Bolivia
    [InlineData(0.0, 0.0)]
    public void Ubicacion_fuera_del_peru_se_rechaza(double lat, double lng)
        => Assert.Equal(UbicacionPeru.FueraDelPeru, UbicacionPeru.Validar((decimal)lat, (decimal)lng, obligatoria: true));

    [Fact]
    public void Una_sola_coordenada_se_rechaza()
    {
        Assert.NotNull(UbicacionPeru.Validar(-12m, null, obligatoria: false));
        Assert.NotNull(UbicacionPeru.Validar(null, -77m, obligatoria: false));
    }

    [Fact]
    public void Sin_coordenadas_solo_es_valido_si_son_opcionales()
    {
        Assert.Null(UbicacionPeru.Validar(null, null, obligatoria: false));
        Assert.NotNull(UbicacionPeru.Validar(null, null, obligatoria: true));
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData(-12.05, null)]
    [InlineData(40.4, -3.7)]
    public async Task Reverse_invalido_no_llega_a_la_base(double? lat, double? lng)
    {
        var (repo, contador) = Proxy<IMaestrosComplementariosRepositorio>();
        var r = await new ObtenerUbigeoPorCoordenadasCasoDeUso(repo).EjecutarAsync((decimal?)lat, (decimal?)lng);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, contador.Llamadas);
    }

    [Fact]
    public async Task Reverse_valido_consulta_la_base()
    {
        var (repo, contador) = Proxy<IMaestrosComplementariosRepositorio>();
        var r = await new ObtenerUbigeoPorCoordenadasCasoDeUso(repo).EjecutarAsync(-14.064m, -75.7286m);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(1, contador.Llamadas);
    }

    [Fact]
    public async Task Guardar_sede_fuera_del_peru_no_llega_a_la_base()
    {
        var (repo, contador) = Proxy<IMaestrosRepositorio>();
        var r = await new GuardarSedeCasoDeUso(repo).EjecutarAsync(Sede(40.4m, -3.7m), "prueba");
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, contador.Llamadas);
    }

    [Fact]
    public async Task Guardar_sede_sin_mapa_sigue_funcionando()
    {
        var (repo, contador) = Proxy<IMaestrosRepositorio>();
        var r = await new GuardarSedeCasoDeUso(repo).EjecutarAsync(Sede(null, null), "prueba");
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(1, contador.Llamadas);
    }

    [Fact]
    public async Task Sedes_sin_ubicacion_rechaza_cliente_invalido()
    {
        var (repo, contador) = Proxy<IMaestrosComplementariosRepositorio>();
        Assert.Equal(1, (await new ObtenerSedesSinUbicacionCasoDeUso(repo).EjecutarAsync(0)).IdTipoMensaje);
        Assert.Equal(0, contador.Llamadas);
        Assert.Equal(2, (await new ObtenerSedesSinUbicacionCasoDeUso(repo).EjecutarAsync(null)).IdTipoMensaje);
    }

    // Repositorio falso genérico: cuenta las llamadas y responde 2 "OK" en cualquier método Task<RespuestaDto<T>>.
    private static (T Repo, RepoContador Contador) Proxy<T>() where T : class
    {
        var repo = DispatchProxy.Create<T, RepoContador>();
        return (repo, (RepoContador)(object)repo);
    }
}

public class RepoContador : DispatchProxy
{
    public int Llamadas { get; private set; }

    protected override object? Invoke(MethodInfo? metodo, object?[]? args)
    {
        Llamadas++;
        var tipoRespuesta = metodo!.ReturnType.GetGenericArguments()[0];
        var respuesta = Activator.CreateInstance(tipoRespuesta, 2, "OK", null);
        return typeof(Task).GetMethod(nameof(Task.FromResult))!.MakeGenericMethod(tipoRespuesta).Invoke(null, [respuesta]);
    }
}
