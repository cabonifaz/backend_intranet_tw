using System.Reflection;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Módulo 13 (OM): la bandeja de metrología solo opera órdenes, propuestas y solicitudes de tipo OM (y la de OS, las suyas).</summary>
public class OrdenesMetrologiaPruebas
{
    private static ValidarTipoOrdenCasoDeUso Validador(string tipo, long? idOs, out TipoFijo repo)
    {
        var proxy = DispatchProxy.Create<IOrdenServicioRepositorio, TipoFijo>();
        repo = (TipoFijo)(object)proxy;
        repo.Respuesta = new RespuestaDto<TipoOrdenDto>(2, "Éxito.", new TipoOrdenDto(tipo, idOs));
        return new ValidarTipoOrdenCasoDeUso(proxy);
    }

    [Fact]
    public async Task Orden_om_pasa_en_la_bandeja_om()
    {
        var r = await Validador("OM", 10, out _).EjecutarAsync("OM", 10, null, null);
        Assert.Equal(2, r.IdTipoMensaje);
    }

    [Fact]
    public async Task Orden_os_se_rechaza_en_la_bandeja_om()
    {
        var r = await Validador("OS", 10, out _).EjecutarAsync("OM", 10, null, null);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Contains("orden de metrología", r.Mensaje);
    }

    [Fact]
    public async Task Propuesta_de_servicio_tecnico_no_genera_om()
    {
        var r = await Validador("OS", null, out _).EjecutarAsync("OM", null, 7, null);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Contains("propuesta", r.Mensaje);
    }

    [Fact]
    public async Task Orden_om_se_rechaza_en_la_bandeja_os()
    {
        var r = await Validador("OM", 10, out _).EjecutarAsync("OS", 10, null, null);
        Assert.Equal(1, r.IdTipoMensaje);
    }

    [Fact]
    public async Task Solicitud_de_otra_orden_se_rechaza()
    {
        var r = await Validador("OM", 99, out _).EjecutarAsync("OM", 10, null, 5);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Contains("no pertenece", r.Mensaje);
    }

    [Fact]
    public async Task Sin_identificadores_no_llega_a_la_base()
    {
        var r = await Validador("OM", 10, out var repo).EjecutarAsync("OM", null, 0, null);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Orden_inexistente_devuelve_el_mensaje_del_sp()
    {
        var validador = Validador("OM", 10, out var repo);
        repo.Respuesta = new RespuestaDto<TipoOrdenDto>(1, "La orden no existe.");
        var r = await validador.EjecutarAsync("OM", 123, null, null);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal("La orden no existe.", r.Mensaje);
    }
}

// Repositorio falso: ObtenerTipoAsync devuelve la respuesta fijada; el resto no se usa aquí.
public class TipoFijo : DispatchProxy
{
    public RespuestaDto<TipoOrdenDto> Respuesta { get; set; } = new(3, "Sin configurar.");
    public int Llamadas { get; private set; }

    protected override object? Invoke(MethodInfo? metodo, object?[]? args)
    {
        Llamadas++;
        return Task.FromResult(Respuesta);
    }
}
