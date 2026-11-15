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
        var direccion = new DireccionFalsa("Calle Lima 123");
        var r = await new ObtenerUbigeoPorCoordenadasCasoDeUso(repo, direccion).EjecutarAsync((decimal?)lat, (decimal?)lng);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, contador.Llamadas);
        Assert.Equal(0, direccion.Llamadas);
    }

    [Fact]
    public async Task Reverse_valido_consulta_la_base()
    {
        var (repo, contador) = Proxy<IMaestrosComplementariosRepositorio>();
        var r = await new ObtenerUbigeoPorCoordenadasCasoDeUso(repo, new DireccionFalsa(null)).EjecutarAsync(-14.064m, -75.7286m);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(1, contador.Llamadas);
    }

    [Fact]
    public async Task Reverse_agrega_la_direccion_al_ubigeo()
    {
        var repo = UbigeoFijo.Crear();
        var r = await new ObtenerUbigeoPorCoordenadasCasoDeUso(repo,new DireccionFalsa("Calle Los Constructores 123")).EjecutarAsync(-14.064m, -75.7286m);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal("110101", r.Datos!.Ubigeo);
        Assert.Equal("Calle Los Constructores 123", r.Datos.Direccion);
    }

    [Fact]
    public async Task Reverse_sin_direccion_igual_devuelve_el_ubigeo()
    {
        var r = await new ObtenerUbigeoPorCoordenadasCasoDeUso(UbigeoFijo.Crear(),new DireccionFalsa(null)).EjecutarAsync(-14.064m, -75.7286m);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal("110101", r.Datos!.Ubigeo);
        Assert.Null(r.Datos.Direccion);
    }

    [Theory]
    [InlineData("""{"road":"Calle Los Constructores","house_number":"123","city":"Ica","country":"Perú"}""", "Calle Los Constructores 123")]
    [InlineData("""{"road":"Avenida Grau","suburb":"Cercado"}""", "Avenida Grau")]
    [InlineData("""{"neighbourhood":"Urb. San José","suburb":"La Tinguiña"}""", "Urb. San José")]
    [InlineData("""{"suburb":"La Tinguiña"}""", "La Tinguiña")]
    [InlineData("""{"hamlet":"Caserío El Huarango","village":"Pueblo"}""", "Caserío El Huarango")]
    [InlineData("""{"village":"Santiago"}""", "Santiago")]
    [InlineData("""{"city":"Ica","state":"Ica","country":"Perú"}""", null)]
    [InlineData("""{"road":"   "}""", null)]
    public void Direccion_de_nominatim_se_arma_corta(string address, string? esperada)
    {
        using var doc = System.Text.Json.JsonDocument.Parse(address);
        Assert.Equal(esperada, TW.Intranet.Infraestructura.Adaptadores.NominatimProveedorDireccion.ArmarDireccion(doc.RootElement));
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

public class DireccionFalsa(string? direccion) : IProveedorDireccion
{
    public int Llamadas { get; private set; }
    public Task<string?> ObtenerDireccionAsync(decimal latitud, decimal longitud, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(direccion);
    }
}

// Repositorio falso que responde el ubigeo de Ica (110101) en cualquier método Task<RespuestaDto<UbigeoReversoDto?>>.
public class UbigeoFijo : DispatchProxy
{
    public static IMaestrosComplementariosRepositorio Crear() => Create<IMaestrosComplementariosRepositorio, UbigeoFijo>();

    protected override object? Invoke(MethodInfo? metodo, object?[]? args)
    {
        var ica = new UbigeoReversoDto(new UbigeoItemDto("11", "ICA"), new UbigeoItemDto("1101", "ICA"), new UbigeoItemDto("110101", "ICA"), "110101", false);
        return Task.FromResult(new RespuestaDto<UbigeoReversoDto?>(2, "Éxito.", ica));
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
