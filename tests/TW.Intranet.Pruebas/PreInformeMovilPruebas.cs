using System.Text;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Adaptadores;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de la cabecera del informe: responde la cabecera configurada (el pre-informe solo la lee).</summary>
internal sealed class InformeCabeceraRepoFalso(RespuestaDto<CabeceraInformeMovilDto> respuesta) : IInformeEquipoMovilRepositorio
{
    public int Llamadas { get; private set; }

    public Task<RespuestaDto<CabeceraInformeMovilDto>> ObtenerCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct, bool previo = false)
    { Llamadas++; return Task.FromResult(respuesta); }

    public Task<RespuestaDto<ResultadoGuardarCabeceraMovilDto>> GuardarCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, string json, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<FotoFallaMovilDto>> RegistrarFotoFallaAsync(long idUsuario, long idOs, long idOsEquipo, string rutaArchivo, decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<CierreEquipoMovilDto>> ValidarCierreAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<InformeGeneradoMovilDto>> GenerarInformeAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) => throw new NotSupportedException();
}

internal sealed class PreInformePdfFalso : IGeneradorPreInformePdf
{
    public int Llamadas { get; private set; }
    public byte[] Generar(DatosPreInformePdf datos) { Llamadas++; return Encoding.ASCII.GetBytes("%PDF-falso"); }
}

/// <summary>Pre-informe: PDF de la cabecera del informe del equipo (solo con la cabecera completa) con espacio para la firma del encargado de planta.</summary>
public class PreInformeMovilPruebas
{
    static PreInformeMovilPruebas() => QuestPDF.Settings.License = LicenseType.Community;

    private static CabeceraInformeMovilDto Completa() => new(
        new DatosInformeMovilDto(1, "OS-000003", "OS", "RQ-1", null, null, false, true, "ANTAMINA S.A.", "20330262428", "Zona Industrial", "Carlos Mendoza", "Jefe", "+51 987", "c@x.com",
            "LOMA", "LCW-6000", "LCW-1", "GAL-1", "EQ-TW-1", "20 000 kg", "10 kg", "10 kg", "Muelle A", "III", "PR-1", "Comercial", "Pedro", "2026-11-19", "08:00", "12:00", "Mantenimiento",
            "Luis Pérez", "Jefe de planta", "999", null),
        new DetalleServicioInformeMovilDto("plataforma", [1.5m, 1.6m], 100m, 200m, true, true, [new PasoChecklistMovilDto("a", "Revisión de celda(s)", 1, true), new PasoChecklistMovilDto("b", "Pintado", 2, false)]),
        [new RecomendacionInformeMovilDto(1, "R1", "Cambiar celda 2", null, "alta", null)], false,
        [new FallaInformeMovilDto(1, "F1", "mecanica", "celda", "Mecánica", "Celda", "Celda con humedad", "media", [5], [new PruebaFallaMovilDto("pesaje", 1, null, 1000m, 1010m, 10m, 20m, "conforme")])], false,
        new PruebasGeneralesMovilDto(true, null, [new LecturaGeneralMovilDto(1, 1000m, 1000m, 0m, 10m, "conforme", false)],
            [new CargaExcentricidadMovilDto(1, 500m, [new LecturaGeneralMovilDto(1, null, 500m, 0m, 10m, "conforme", false), new LecturaGeneralMovilDto(2, null, 510m, 10m, 10m, "no_conforme", false)])]),
        "Todo correcto",
        new DiagnosticoInformeMovilDto("media", "operativo", false, true, false, false),
        new OpcionesInformeMovilDto([new OpcionInformeMovilDto("plataforma", "Balanza de plataforma", null)], [], []));

    private static RespuestaDto<CabeceraInformeMovilDto> Ok(CabeceraInformeMovilDto c) => new(2, "Éxito.", c);

    // ── Regla de cabecera completa ──────────────────────────────────────────

    [Fact]
    public void Cabecera_completa_no_tiene_pendientes()
        => Assert.Empty(ReglasPreInformeMovil.Pendientes(Completa()));

    [Fact]
    public void Sin_encargado_de_planta_falta_ese_dato()
    {
        var c = Completa();
        var sin = c with { Datos = c.Datos with { ResponsableNombre = "  " } };
        Assert.Equal(["Quién atiende en planta"], ReglasPreInformeMovil.Pendientes(sin));
    }

    [Fact]
    public void Una_falla_sin_prueba_deja_las_fallas_pendientes()
    {
        var c = Completa();
        var sin = c with { Fallas = [c.Fallas[0] with { Pruebas = [] }] };
        Assert.Equal(["Fallas y su prueba"], ReglasPreInformeMovil.Pendientes(sin));
    }

    [Fact]
    public void Sin_fallas_basta_marcar_que_no_hay()
    {
        var c = Completa();
        Assert.Empty(ReglasPreInformeMovil.Pendientes(c with { Fallas = [], SinFallas = true }));
        Assert.Equal(["Fallas y su prueba"], ReglasPreInformeMovil.Pendientes(c with { Fallas = [], SinFallas = false }));
    }

    [Fact]
    public void Sin_recomendaciones_ni_marca_de_que_no_hay_falta_el_bloque()
    {
        var c = Completa();
        Assert.Equal(["Recomendaciones inmediatas"], ReglasPreInformeMovil.Pendientes(c with { Recomendaciones = [], SinRecomendaciones = false }));
        Assert.Empty(ReglasPreInformeMovil.Pendientes(c with { Recomendaciones = [], SinRecomendaciones = true }));
    }

    [Fact]
    public void Faltan_ensayos_detalle_y_diagnostico()
    {
        var c = Completa();
        var sin = c with
        {
            Detalle = c.Detalle with { Guardado = false },
            PruebasGenerales = c.PruebasGenerales with { Finalizado = false },
            Diagnostico = c.Diagnostico with { EstadoEquipo = null },
        };
        Assert.Equal(3, ReglasPreInformeMovil.Pendientes(sin).Count);
    }

    // ── Caso de uso ─────────────────────────────────────────────────────────

    [Fact]
    public async Task Cabecera_completa_genera_el_pdf()
    {
        var pdf = new PreInformePdfFalso();
        var r = await new GenerarPreInformeMovilCasoDeUso(new InformeCabeceraRepoFalso(Ok(Completa())), pdf).EjecutarAsync(5, 1, 2);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.NotEmpty(r.Datos!);
        Assert.Equal(1, pdf.Llamadas);
    }

    [Fact]
    public async Task Cabecera_incompleta_no_genera_el_pdf_y_dice_que_falta()
    {
        var c = Completa();
        var pdf = new PreInformePdfFalso();
        var r = await new GenerarPreInformeMovilCasoDeUso(new InformeCabeceraRepoFalso(Ok(c with { Diagnostico = c.Diagnostico with { SeveridadGeneral = null } })), pdf).EjecutarAsync(5, 1, 2);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Contains("Diagnóstico final", r.Mensaje);
        Assert.Equal(0, pdf.Llamadas);
    }

    [Fact]
    public async Task Sin_acceso_al_equipo_se_devuelve_el_mensaje_del_sp()
    {
        var pdf = new PreInformePdfFalso();
        var r = await new GenerarPreInformeMovilCasoDeUso(new InformeCabeceraRepoFalso(new(1, "Servicio no encontrado.")), pdf).EjecutarAsync(5, 1, 2);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal("Servicio no encontrado.", r.Mensaje);
        Assert.Equal(0, pdf.Llamadas);
    }

    [Theory]
    [InlineData(0, 1, 2)]
    [InlineData(5, 0, 2)]
    [InlineData(5, 1, 0)]
    public async Task Ids_no_validos_no_llegan_al_repositorio(long idUsuario, long idOs, long idOsEquipo)
    {
        var repo = new InformeCabeceraRepoFalso(Ok(Completa()));
        var r = await new GenerarPreInformeMovilCasoDeUso(repo, new PreInformePdfFalso()).EjecutarAsync(idUsuario, idOs, idOsEquipo);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    // ── Generador real ──────────────────────────────────────────────────────

    [Fact]
    public void El_generador_real_produce_un_pdf_valido()
    {
        var bytes = new GeneradorPreInformePdf().Generar(new DatosPreInformePdf(Completa(), new DateTime(2026, 11, 19, 16, 30, 0)));

        Assert.True(bytes.Length > 1000);
        Assert.Equal("%PDF", Encoding.ASCII.GetString(bytes, 0, 4));
    }

    [Fact]
    public void El_generador_real_soporta_una_cabecera_sin_fallas_ni_lecturas()
    {
        var c = Completa() with { Fallas = [], SinFallas = true, Recomendaciones = [], SinRecomendaciones = true, PruebasGenerales = new PruebasGeneralesMovilDto(true, null, [], []) };
        var bytes = new GeneradorPreInformePdf().Generar(new DatosPreInformePdf(c, DateTime.UtcNow));

        Assert.Equal("%PDF", Encoding.ASCII.GetString(bytes, 0, 4));
    }

    [Theory]
    [InlineData(1, "Centro")]
    [InlineData(2, "Esquina 2")]
    [InlineData(5, "Esquina 5")]
    [InlineData(null, "—")]
    public void Posiciones_de_excentricidad_como_en_la_app(int? posicion, string esperado)
        => Assert.Equal(esperado, GeneradorPreInformePdf.Posicion(posicion));
}
