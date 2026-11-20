using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio del registro fotográfico: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class EvidenciasRepoFalso : IEvidenciasMovilRepositorio
{
    public bool PuedeRegistrar { get; set; } = true;
    public int Llamadas { get; private set; }
    public (string Codigo, int Pagina, string? Ruta, string IaEstado)? Registrado { get; private set; }
    public long? Quitada { get; private set; }

    private RespuestaDto<EvidenciasMovilDto> Panel() => new(2, "OK", new EvidenciasMovilDto(
        new CabeceraEvidenciasMovilDto(1, 2, "OS-000003", "Balanza", 1, null, null, null, null, null, null, "en_ejecucion", PuedeRegistrar, null, 9, 0, 0, 0, 2, false),
        [], []));

    public Task<RespuestaDto<EvidenciasMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) => Task.FromResult(Panel());

    public Task<RespuestaDto<ResultadoEvidenciaMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, long idOsEquipo, string codigo, int pagina, string? rutaArchivo, string? rutaCuadro, decimal? duracionSeg,
        decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, string? qrTexto, ResultadoValidacionEvidenciaIa ia, CancellationToken ct)
    {
        Llamadas++;
        Registrado = (codigo, pagina, rutaArchivo, ia.Estado);
        return Task.FromResult(new RespuestaDto<ResultadoEvidenciaMovilDto>(2, "Foto adicional guardada.", new ResultadoEvidenciaMovilDto(77, ia.Estado, null, 1, null, null, null, "Foto adicional guardada.")));
    }

    public Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> ForzarAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<ResultadoForzarEvidenciaMovilDto>(1, "No")); }

    public Task<RespuestaDto<object>> QuitarAdicionalAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct)
    { Llamadas++; Quitada = idEvidencia; return Task.FromResult(new RespuestaDto<object>(2, "Foto adicional quitada.")); }

    public Task<RespuestaDto<ArchivoEvidenciaMovilDto>> ObtenerArchivoAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<ArchivoEvidenciaMovilDto>(1, "No")); }
}

internal sealed class ValidadorIaFalso : IValidadorEvidenciaIa
{
    public int Llamadas { get; private set; }
    public Task<ResultadoValidacionEvidenciaIa> ValidarAsync(SolicitudValidacionEvidenciaIa solicitud, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new ResultadoValidacionEvidenciaIa("aprobada", null, null)); }
}

/// <summary>Fotos adicionales del Registro fotográfico: extras opcionales, sin IA y fuera de las 9 del panel.</summary>
public class FotosAdicionalesMovilPruebas
{
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

    private static CapturaEvidenciaMovilDto Captura(string codigo, int pagina = 1) => new(codigo, pagina, null, null, null, null, null, null);

    private static (RegistrarEvidenciaMovilCasoDeUso Caso, EvidenciasRepoFalso Repo, ValidadorIaFalso Ia, AlmacenFalso Almacen) Armar()
    {
        var repo = new EvidenciasRepoFalso();
        var ia = new ValidadorIaFalso();
        var almacen = new AlmacenFalso();
        return (new RegistrarEvidenciaMovilCasoDeUso(repo, ia, almacen), repo, ia, almacen);
    }

    [Fact]
    public void Adicional_es_un_codigo_valido_y_no_exige_numero_de_hoja()
        => Assert.Null(RegistrarEvidenciaMovilCasoDeUso.Validar(Captura("adicional", 99)));

    [Fact]
    public void El_informe_sigue_limitado_a_diez_hojas()
    {
        Assert.NotNull(RegistrarEvidenciaMovilCasoDeUso.Validar(Captura("informe", 11)));
        Assert.Null(RegistrarEvidenciaMovilCasoDeUso.Validar(Captura("informe", 10)));
    }

    [Fact]
    public void Un_codigo_desconocido_se_rechaza()
        => Assert.NotNull(RegistrarEvidenciaMovilCasoDeUso.Validar(Captura("adicionales")));

    [Fact]
    public async Task Adicional_se_guarda_sin_pasar_por_la_ia_y_queda_omitida()
    {
        var (caso, repo, ia, almacen) = Armar();
        await using var foto = new MemoryStream(Jpeg);

        var r = await caso.EjecutarAsync(5, 1, 2, Captura("adicional"), foto, foto.Length, null, 0);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(0, ia.Llamadas);
        Assert.Equal("adicional", repo.Registrado!.Value.Codigo);
        Assert.Equal("omitida", repo.Registrado.Value.IaEstado);
        Assert.Single(almacen.Archivos);
    }

    [Fact]
    public async Task Una_evidencia_del_panel_si_pasa_por_la_ia()
    {
        var (caso, repo, ia, _) = Armar();
        await using var foto = new MemoryStream(Jpeg);

        await caso.EjecutarAsync(5, 1, 2, Captura("inicial"), foto, foto.Length, null, 0);

        Assert.Equal(1, ia.Llamadas);
        Assert.Equal("aprobada", repo.Registrado!.Value.IaEstado);
    }

    [Fact]
    public async Task Adicional_que_no_es_jpeg_se_rechaza_y_no_se_guarda()
    {
        var (caso, repo, _, almacen) = Armar();
        await using var archivo = new MemoryStream([1, 2, 3, 4, 5, 6, 7, 8]);

        var r = await caso.EjecutarAsync(5, 1, 2, Captura("adicional"), archivo, archivo.Length, null, 0);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Null(repo.Registrado);
        Assert.Empty(almacen.Archivos);
    }

    [Fact]
    public async Task Adicional_con_el_equipo_pausado_no_se_registra()
    {
        var (caso, repo, _, _) = Armar();
        repo.PuedeRegistrar = false;
        await using var foto = new MemoryStream(Jpeg);

        var r = await caso.EjecutarAsync(5, 1, 2, Captura("adicional"), foto, foto.Length, null, 0);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Null(repo.Registrado);
    }

    [Fact]
    public async Task Quitar_delega_en_el_sp_y_devuelve_el_panel()
    {
        var repo = new EvidenciasRepoFalso();
        var r = await new QuitarEvidenciaAdicionalMovilCasoDeUso(repo).EjecutarAsync(5, 1, 2, 77);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(77, repo.Quitada);
        Assert.NotNull(r.Datos);
    }

    [Theory]
    [InlineData(0, 1, 2, 3)]
    [InlineData(5, 0, 2, 3)]
    [InlineData(5, 1, 0, 3)]
    [InlineData(5, 1, 2, 0)]
    public async Task Quitar_con_ids_no_validos_no_llega_al_sp(long idUsuario, long idOs, long idOsEquipo, long idEvidencia)
    {
        var repo = new EvidenciasRepoFalso();
        var r = await new QuitarEvidenciaAdicionalMovilCasoDeUso(repo).EjecutarAsync(idUsuario, idOs, idOsEquipo, idEvidencia);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }
}
