using System.Text.Json;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de Mi equipo: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class EquipoRepoFalso : IEquipoJefaturaMovilRepositorio
{
    public int Llamadas { get; private set; }
    public (long IdUsuario, long IdTecnico, string? Mes)? Horas { get; private set; }

    public static EquipoTecnicoDto Tecnico() =>
        new(9, "Joao Gutiérrez", "JG", "Técnico de Campo", "tardanza", "En labores · 07:58 (tardanza 13 min)", "07:58", 13, 849, "OS-000849", "OS", "en_ruta", "Planta Ate", null, -12.06m, -77.02m, 3);

    public Task<RespuestaDto<EquipoJefaturaDto>> ObtenerAsync(long idUsuario, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(new RespuestaDto<EquipoJefaturaDto>(2, "OK", new EquipoJefaturaDto(new EquipoKpisDto(8, 1, 1, 1, 0, 11, "10:46", 30, 10), [Tecnico()])));
    }

    public Task<RespuestaDto<FichaEquipoTecnicoDto>> ObtenerFichaAsync(long idUsuario, long idTecnico, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(new RespuestaDto<FichaEquipoTecnicoDto>(1, "El técnico no pertenece a tu equipo."));
    }

    public Task<RespuestaDto<HorasTecnicoLecturaDto>> ObtenerHorasAsync(long idUsuario, long idTecnico, string? mes, CancellationToken ct)
    {
        Llamadas++;
        Horas = (idUsuario, idTecnico, mes);
        var dias = new List<HoraDiaDto>
        {
            new("2026-11-02", 480, 2, "08:00", "17:00", false, [new HoraServicioDto(1, "OS-000001", "08:00", "12:00", 240), new HoraServicioDto(2, "OS-000002", "13:00", "17:00", 240)]),
            new("2026-11-10", 300, 1, "09:00", "14:00", false, []),
            new("2026-11-17", 0, 1, null, null, true, [new HoraServicioDto(3, "OS-000003", "10:00", null, 0)]),
        };
        return Task.FromResult(new RespuestaDto<HorasTecnicoLecturaDto>(2, "OK",
            new HorasTecnicoLecturaDto(Tecnico(), mes ?? "2026-11", dias, 780, 2, 4, false, [new HoraMesDto("2026-11", 780, 2, 4, false), new HoraMesDto("2026-10", 9000, 21, 40, true)])));
    }
}

/// <summary>HU-36 Mi equipo desde la app: validación del mes, cálculo de las semanas (acumulado semanal), delegación al SP (las reglas de alcance, estado, SSOMA y horas las valida el procedimiento).</summary>
public class EquipoJefaturaMovilPruebas
{
    private static readonly DateOnly Hoy = new(2026, 11, 18);

    // ── Validación del mes ──────────────────────────────────────────────────

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Mes_vacio_significa_el_mes_actual(string? mes)
    {
        var v = ValidacionEquipoJefaturaMovil.NormalizarMes(mes, Hoy);
        Assert.Null(v.Error);
        Assert.Null(v.Mes);
    }

    [Theory]
    [InlineData("2026-11")]
    [InlineData(" 2026-10 ")]
    [InlineData("2024-12")]   // justo 24 meses (nov-2026 → dic-2024)
    public void Mes_valido_se_normaliza(string mes)
    {
        var v = ValidacionEquipoJefaturaMovil.NormalizarMes(mes, Hoy);
        Assert.Null(v.Error);
        Assert.Equal(mes.Trim(), v.Mes);
    }

    [Theory]
    [InlineData("2026-13")]
    [InlineData("2026-00")]
    [InlineData("26-11")]
    [InlineData("2026/11")]
    [InlineData("2026-11-01")]
    [InlineData("noviembre")]
    [InlineData("2026-11'; DROP TABLE usuario;--")]
    public void Mes_con_formato_invalido_se_rechaza(string mes)
        => Assert.Equal(ValidacionEquipoJefaturaMovil.MensajeMesInvalido, ValidacionEquipoJefaturaMovil.NormalizarMes(mes, Hoy).Error);

    [Fact]
    public void Mes_futuro_se_rechaza()
        => Assert.Equal(ValidacionEquipoJefaturaMovil.MensajeMesFuturo, ValidacionEquipoJefaturaMovil.NormalizarMes("2026-12", Hoy).Error);

    [Fact]
    public void Mes_de_hace_mas_de_24_meses_se_rechaza()
        => Assert.Equal(ValidacionEquipoJefaturaMovil.MensajeMesAntiguo, ValidacionEquipoJefaturaMovil.NormalizarMes("2024-11", Hoy).Error);

    // ── Semanas (acumulado semanal) ─────────────────────────────────────────

    [Fact]
    public void Semanas_son_de_lunes_a_domingo_y_cuentan_solo_los_dias_del_mes()
    {
        // Noviembre 2026: el 1 es domingo, así que la primera semana va del lun 26/10 al dom 01/11 (solo cuenta el 01).
        var dias = new List<HoraDiaDto>
        {
            new("2026-11-01", 60, 1, null, null, false, []),
            new("2026-11-02", 480, 2, null, null, false, []),
            new("2026-11-03", 240, 1, null, null, false, []),
            new("2026-11-17", 0, 1, null, null, true, []),
            new("2026-11-30", 120, 1, null, null, false, []),
        };
        var semanas = CalculoHorasEquipo.ArmarSemanas("2026-11", dias);

        Assert.Equal(6, semanas.Count);
        Assert.Equal(new HoraSemanaDto("2026-10-26", "2026-11-01", 60, 1), semanas[0]);
        Assert.Equal(new HoraSemanaDto("2026-11-02", "2026-11-08", 720, 2), semanas[1]);
        Assert.Equal(new HoraSemanaDto("2026-11-09", "2026-11-15", 0, 0), semanas[2]);
        Assert.Equal(new HoraSemanaDto("2026-11-16", "2026-11-22", 0, 0), semanas[3]);     // el día 17 está sin cierre: 0 minutos y no cuenta como día trabajado
        Assert.Equal(new HoraSemanaDto("2026-11-23", "2026-11-29", 0, 0), semanas[4]);
        Assert.Equal(new HoraSemanaDto("2026-11-30", "2026-12-06", 120, 1), semanas[5]);
    }

    [Fact]
    public void La_suma_de_las_semanas_es_el_total_del_mes()
    {
        var dias = new List<HoraDiaDto>
        {
            new("2026-02-01", 90, 1, null, null, false, []),
            new("2026-02-09", 300, 1, null, null, false, []),
            new("2026-02-28", 45, 1, null, null, false, []),
        };
        var semanas = CalculoHorasEquipo.ArmarSemanas("2026-02", dias);
        Assert.Equal(dias.Sum(d => d.Minutos), semanas.Sum(s => s.Minutos));
        Assert.Equal("2026-01-26", semanas[0].Desde);   // el 1 de febrero de 2026 es domingo
        Assert.Equal("2026-03-01", semanas[^1].Hasta);
    }

    [Fact]
    public void Mes_sin_datos_arma_las_semanas_en_cero()
    {
        var semanas = CalculoHorasEquipo.ArmarSemanas("2026-09", []);
        Assert.NotEmpty(semanas);
        Assert.All(semanas, s => Assert.Equal((0, 0), (s.Minutos, s.DiasTrabajados)));
    }

    // ── Casos de uso ────────────────────────────────────────────────────────

    [Fact]
    public async Task Sin_usuario_del_token_o_con_tecnico_invalido_no_se_consulta_nada()
    {
        var repo = new EquipoRepoFalso();
        Assert.Equal(1, (await new ObtenerEquipoJefaturaMovilCasoDeUso(repo).EjecutarAsync(0)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerFichaEquipoTecnicoMovilCasoDeUso(repo).EjecutarAsync(0, 5)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerFichaEquipoTecnicoMovilCasoDeUso(repo).EjecutarAsync(7, 0)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerHorasTecnicoMovilCasoDeUso(repo).EjecutarAsync(0, 5, null)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerHorasTecnicoMovilCasoDeUso(repo).EjecutarAsync(7, -2, null)).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Horas_con_mes_invalido_no_llama_al_repositorio()
    {
        var repo = new EquipoRepoFalso();
        var r = await new ObtenerHorasTecnicoMovilCasoDeUso(repo).EjecutarAsync(7, 9, "2026-13");
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(ValidacionEquipoJefaturaMovil.MensajeMesInvalido, r.Mensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Horas_arma_las_semanas_a_partir_de_los_dias_y_conserva_el_historial()
    {
        var repo = new EquipoRepoFalso();
        var r = await new ObtenerHorasTecnicoMovilCasoDeUso(repo).EjecutarAsync(7, 9, "2026-11");
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal((7L, 9L, "2026-11"), repo.Horas);
        var d = r.Datos!;
        Assert.Equal("2026-11", d.Mes);
        Assert.Equal(780, d.TotalMinutos);
        Assert.Equal(d.Dias.Sum(x => x.Minutos), d.Semanas.Sum(s => s.Minutos));
        Assert.Equal(2, d.Historial.Count);
        Assert.True(d.Historial[1].Cerrado);
        Assert.True(d.Dias[2].SinCierre);
    }

    [Fact]
    public async Task Horas_sin_mes_deja_que_el_procedimiento_use_el_mes_actual()
    {
        var repo = new EquipoRepoFalso();
        await new ObtenerHorasTecnicoMovilCasoDeUso(repo).EjecutarAsync(7, 9, "  ");
        Assert.Null(repo.Horas!.Value.Mes);
    }

    [Fact]
    public async Task Lista_y_ficha_delegan_en_el_repositorio_y_respetan_el_mensaje_de_negocio()
    {
        var repo = new EquipoRepoFalso();
        Assert.Equal(2, (await new ObtenerEquipoJefaturaMovilCasoDeUso(repo).EjecutarAsync(7)).IdTipoMensaje);
        var ficha = await new ObtenerFichaEquipoTecnicoMovilCasoDeUso(repo).EjecutarAsync(7, 5);
        Assert.Equal(1, ficha.IdTipoMensaje);
        Assert.Equal("El técnico no pertenece a tu equipo.", ficha.Mensaje);
        Assert.Equal(2, repo.Llamadas);
    }

    // ── Serialización: los nombres que consume la app ───────────────────────

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    [Fact]
    public void Lista_serializa_los_nombres_acordados_en_camelCase()
    {
        var json = JsonSerializer.Serialize(new EquipoJefaturaDto(new EquipoKpisDto(8, 1, 1, 1, 0, 11, "10:46", 30, 10), [EquipoRepoFalso.Tecnico()]), Web);
        using var doc = JsonDocument.Parse(json);
        var raiz = doc.RootElement;
        foreach (var k in new[] { "enLabores", "refrigerio", "tardanza", "sinMarcar", "finalizaron", "total", "actualizado", "refrescoSegundos", "enJornada" })
            Assert.True(raiz.GetProperty("kpis").TryGetProperty(k, out _), k);
        var t = raiz.GetProperty("tecnicos")[0];
        foreach (var k in new[] { "idUsuario", "nombre", "iniciales", "cargo", "estado", "detalle", "horaInicio", "minutosTardanza", "idOs", "numeroOs", "tipoOs", "estadoServicio", "lugar",
                                  "motivoSinServicio", "latitud", "longitud", "minutosUbicacion" })
            Assert.True(t.TryGetProperty(k, out _), k);
    }

    [Fact]
    public void Ficha_serializa_los_nombres_acordados_en_camelCase()
    {
        var ficha = new FichaEquipoTecnicoDto(EquipoRepoFalso.Tecnico(), "987654321", "servicio_tecnico", new SsomaTecnicoDto("conforme", null),
            [new MarcacionEquipoDto("inicio_labores", "Inicio de labores", "07:58", "Tardanza 13 min (programado 07:45)", "hecho", "naranja")],
            new CargaSemanaDto("2026-11-16", "2026-11-20", [new CargaDiaEquipoDto("2026-11-16", "Lun", 8m, 100)], 92, "alta", 36.8m, 40m));
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(ficha, Web));
        var raiz = doc.RootElement;
        foreach (var k in new[] { "tecnico", "telefono", "area", "ssoma", "marcaciones", "carga" }) Assert.True(raiz.TryGetProperty(k, out _), k);
        foreach (var k in new[] { "estado", "detalle" }) Assert.True(raiz.GetProperty("ssoma").TryGetProperty(k, out _), k);
        foreach (var k in new[] { "tipo", "titulo", "hora", "detalle", "estado", "tono" }) Assert.True(raiz.GetProperty("marcaciones")[0].TryGetProperty(k, out _), k);
        var carga = raiz.GetProperty("carga");
        foreach (var k in new[] { "desde", "hasta", "dias", "utilizacionPct", "nivel", "horasPlanificadas", "horasCapacidad" }) Assert.True(carga.TryGetProperty(k, out _), k);
        foreach (var k in new[] { "fecha", "etiqueta", "horas", "porcentaje" }) Assert.True(carga.GetProperty("dias")[0].TryGetProperty(k, out _), k);
    }

    [Fact]
    public async Task Horas_serializa_los_nombres_acordados_en_camelCase()
    {
        var r = await new ObtenerHorasTecnicoMovilCasoDeUso(new EquipoRepoFalso()).EjecutarAsync(7, 9, "2026-11");
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(r.Datos, Web));
        var raiz = doc.RootElement;
        foreach (var k in new[] { "tecnico", "mes", "dias", "semanas", "totalMinutos", "diasTrabajados", "servicios", "cerrado", "historial" }) Assert.True(raiz.TryGetProperty(k, out _), k);
        var dia = raiz.GetProperty("dias")[0];
        foreach (var k in new[] { "fecha", "minutos", "servicios", "inicio", "fin", "sinCierre", "detalle" }) Assert.True(dia.TryGetProperty(k, out _), k);
        foreach (var k in new[] { "idOs", "numero", "inicio", "fin", "minutos" }) Assert.True(dia.GetProperty("detalle")[0].TryGetProperty(k, out _), k);
        foreach (var k in new[] { "desde", "hasta", "minutos", "diasTrabajados" }) Assert.True(raiz.GetProperty("semanas")[0].TryGetProperty(k, out _), k);
        foreach (var k in new[] { "mes", "minutos", "diasTrabajados", "servicios", "cerrado" }) Assert.True(raiz.GetProperty("historial")[0].TryGetProperty(k, out _), k);
    }
}
