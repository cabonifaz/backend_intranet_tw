using System.Text.Json;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de los viáticos del equipo: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class ViaticosEquipoRepoFalso : IViaticosEquipoMovilRepositorio
{
    public int Llamadas { get; private set; }
    public (long IdUsuario, long IdOs, long IdTecnico, decimal Mov, decimal Ali, decimal Alo, decimal Otr, bool Dep, string Version)? Asignado { get; private set; }

    public Task<RespuestaDto<ViaticosEquipoDto>> ObtenerAsync(long idUsuario, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(new RespuestaDto<ViaticosEquipoDto>(2, "OK", new ViaticosEquipoDto(new ViaticosEquipoKpisDto(0, 0, 0, null, 30), [])));
    }

    public Task<RespuestaDto<ViaticoServicioDto>> ObtenerServicioAsync(long idUsuario, long idOs, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(new RespuestaDto<ViaticoServicioDto>(1, "sin datos"));
    }

    public Task<RespuestaDto<AsignacionViaticoResultadoDto>> AsignarAsync(long idUsuario, long idOs, long idTecnico, decimal movilidad, decimal alimentacion, decimal alojamiento, decimal otros,
                                                                          bool depositado, string version, CancellationToken ct)
    {
        Llamadas++;
        Asignado = (idUsuario, idOs, idTecnico, movilidad, alimentacion, alojamiento, otros, depositado, version);
        return Task.FromResult(new RespuestaDto<AsignacionViaticoResultadoDto>(2, "OK", new AsignacionViaticoResultadoDto(350m, depositado, 2, "5-350-123")));
    }
}

/// <summary>HU-35 viáticos y gastos del equipo desde la app: validación de entrada y delegación al SP (las reglas de negocio de HU-45 las valida el procedimiento).</summary>
public class ViaticosEquipoMovilPruebas
{
    private static AsignarViaticoEquipoDto Asignacion() => new(9, 150m, 120m, 80m, 0m, false, "5-350-123");

    // ── Validación de la asignación ─────────────────────────────────────────

    [Fact]
    public void Asignacion_valida_se_normaliza_y_vacio_es_cero()
    {
        var v = ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 150m, null, 80.5m, null, null, "  5-350-123 "));
        Assert.Null(v.Error);
        Assert.Equal(9, v.IdTecnico);
        Assert.Equal((150m, 0m, 80.5m, 0m), (v.Movilidad, v.Alimentacion, v.Alojamiento, v.Otros));
        Assert.False(v.Depositado);
        Assert.Equal("5-350-123", v.Version);
    }

    [Fact]
    public void Asignacion_sin_cuerpo_se_rechaza()
        => Assert.NotNull(ValidacionViaticosEquipoMovil.NormalizarAsignacion(null).Error);

    [Theory]
    [InlineData(null)]
    [InlineData(0L)]
    [InlineData(-3L)]
    public void Asignacion_sin_tecnico_valido_se_rechaza(long? idTecnico)
        => Assert.Contains("técnico", ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(idTecnico, 10m, 0m, 0m, 0m, false, "v")).Error!);

    [Fact]
    public void Asignacion_rechaza_montos_negativos()
        => Assert.Contains("negativos", ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, -1m, 50m, 0m, 0m, false, "v")).Error!);

    [Fact]
    public void Asignacion_rechaza_mas_de_dos_decimales()
        => Assert.Contains("decimales", ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 10.123m, 0m, 0m, 0m, false, "v")).Error!);

    [Fact]
    public void Asignacion_rechaza_montos_desmedidos()
        => Assert.NotNull(ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 99_999_999m, 0m, 0m, 0m, false, "v")).Error);

    [Fact]
    public void Asignacion_exige_al_menos_un_monto_mayor_a_cero()
        => Assert.Contains("al menos un monto", ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 0m, null, 0m, 0m, false, "v")).Error!);

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public void Asignacion_exige_la_version(string? version)
        => Assert.Contains("versión", ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 10m, 0m, 0m, 0m, false, version)).Error!);

    [Fact]
    public void Asignacion_rechaza_version_larga_o_con_caracteres_de_control()
    {
        Assert.NotNull(ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 10m, 0m, 0m, 0m, false, new string('9', 81))).Error);
        Assert.NotNull(ValidacionViaticosEquipoMovil.NormalizarAsignacion(new AsignarViaticoEquipoDto(9, 10m, 0m, 0m, 0m, false, "5-1\n-9")).Error);
    }

    // ── Casos de uso ────────────────────────────────────────────────────────

    [Fact]
    public async Task Asignar_rechaza_entrada_invalida_sin_llamar_al_repositorio()
    {
        var repo = new ViaticosEquipoRepoFalso();
        var r = await new AsignarViaticoEquipoMovilCasoDeUso(repo).EjecutarAsync(7, 12, new AsignarViaticoEquipoDto(9, 0m, 0m, 0m, 0m, false, "v"));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Asignar_pasa_los_valores_normalizados_al_repositorio()
    {
        var repo = new ViaticosEquipoRepoFalso();
        var r = await new AsignarViaticoEquipoMovilCasoDeUso(repo).EjecutarAsync(7, 12, new AsignarViaticoEquipoDto(9, 150m, 120m, 80m, null, true, " 5-350-123 "));
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal((7L, 12L, 9L, 150m, 120m, 80m, 0m, true, "5-350-123"), repo.Asignado);
        Assert.True(r.Datos!.Depositado);
    }

    [Fact]
    public async Task Sin_usuario_del_token_o_con_servicio_invalido_no_se_consulta_nada()
    {
        var repo = new ViaticosEquipoRepoFalso();
        Assert.Equal(1, (await new ObtenerViaticosEquipoMovilCasoDeUso(repo).EjecutarAsync(0)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerViaticoServicioEquipoMovilCasoDeUso(repo).EjecutarAsync(0, 5)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerViaticoServicioEquipoMovilCasoDeUso(repo).EjecutarAsync(7, 0)).IdTipoMensaje);
        Assert.Equal(1, (await new AsignarViaticoEquipoMovilCasoDeUso(repo).EjecutarAsync(0, 5, Asignacion())).IdTipoMensaje);
        Assert.Equal(1, (await new AsignarViaticoEquipoMovilCasoDeUso(repo).EjecutarAsync(7, 0, Asignacion())).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Lista_y_detalle_delegan_en_el_repositorio()
    {
        var repo = new ViaticosEquipoRepoFalso();
        Assert.Equal(2, (await new ObtenerViaticosEquipoMovilCasoDeUso(repo).EjecutarAsync(7)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerViaticoServicioEquipoMovilCasoDeUso(repo).EjecutarAsync(7, 5)).IdTipoMensaje);
        Assert.Equal(2, repo.Llamadas);
    }

    // ── Serialización: los nombres que consume la app ───────────────────────

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    [Fact]
    public void Lista_serializa_los_nombres_acordados_en_camelCase()
    {
        var dto = new ViaticosEquipoDto(
            new ViaticosEquipoKpisDto(1650m, 1102m, 85m, "10:46", 30),
            [new ViaticoEquipoServicioDto(845, "OS-0845-2026", "Molinos del Sur", 77, "Juan Pérez, Luis Medina", 2, 450m, 450m, 267.5m, 45m, 2, 59, "por_revisar", true)]);

        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(dto, Web));
        var k = doc.RootElement.GetProperty("kpis");
        Assert.Equal(1650m, k.GetProperty("asignado").GetDecimal());
        Assert.Equal(85m, k.GetProperty("porRevisar").GetDecimal());
        Assert.Equal(30, k.GetProperty("refrescoSegundos").GetInt32());
        var s = doc.RootElement.GetProperty("servicios")[0];
        Assert.Equal("OS-0845-2026", s.GetProperty("numeroOs").GetString());
        Assert.Equal(77, s.GetProperty("idProgramacion").GetInt64());
        Assert.Equal("Juan Pérez, Luis Medina", s.GetProperty("tecnicos").GetString());
        Assert.Equal(2, s.GetProperty("nTecnicos").GetInt32());
        Assert.Equal(2, s.GetProperty("gastosPorRevisar").GetInt32());
        Assert.Equal(59, s.GetProperty("avance").GetInt32());
        Assert.Equal("por_revisar", s.GetProperty("estado").GetString());
        Assert.True(s.GetProperty("puedeAsignar").GetBoolean());
    }

    [Fact]
    public void Detalle_y_resultado_serializan_los_nombres_acordados_en_camelCase()
    {
        var detalle = new ViaticoServicioDto(
            new ViaticoServicioCabeceraDto(845, "OS-0845-2026", "Molinos del Sur", 77, false, false, "El servicio ya salió a campo.", "5-350-123", 450m, 150m, 267.5m, 45m),
            [new ViaticoTecnicoDto(9, "Juan Pérez", true, 350m, 150m, 267.5m, 45m, [new ViaticoLineaDto(31, "Movilidad / Transporte", "movilidad", 150m, true)])],
            [new ViaticoGastoDto(40, 9, "Juan Pérez", "Peaje", 22.5m, "pendiente", "2026-11-17", true, 12.5m, false)]);

        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(detalle, Web));
        var c = doc.RootElement.GetProperty("cabecera");
        Assert.False(c.GetProperty("puedeAsignar").GetBoolean());
        Assert.Equal("El servicio ya salió a campo.", c.GetProperty("motivoNoAsignar").GetString());
        Assert.Equal("5-350-123", c.GetProperty("version").GetString());
        var t = doc.RootElement.GetProperty("tecnicos")[0];
        Assert.True(t.GetProperty("principal").GetBoolean());
        Assert.Equal("movilidad", t.GetProperty("lineas")[0].GetProperty("clave").GetString());
        Assert.True(t.GetProperty("lineas")[0].GetProperty("depositado").GetBoolean());
        var g = doc.RootElement.GetProperty("gastos")[0];
        Assert.Equal(12.5m, g.GetProperty("montoIa").GetDecimal());
        Assert.False(g.GetProperty("coincideIa").GetBoolean());
        Assert.True(g.GetProperty("tieneComprobante").GetBoolean());
        Assert.Equal("2026-11-17", g.GetProperty("fecha").GetString());

        using var res = JsonDocument.Parse(JsonSerializer.Serialize(new AsignacionViaticoResultadoDto(350m, true, 2, "5-350-123"), Web));
        Assert.Equal(350m, res.RootElement.GetProperty("total").GetDecimal());
        Assert.True(res.RootElement.GetProperty("depositado").GetBoolean());
        Assert.Equal(2, res.RootElement.GetProperty("notificados").GetInt32());
        Assert.Equal("5-350-123", res.RootElement.GetProperty("version").GetString());
    }

    [Fact]
    public void Cuerpo_de_asignacion_se_lee_en_camelCase()
    {
        var dto = JsonSerializer.Deserialize<AsignarViaticoEquipoDto>(
            """{"idTecnico":9,"movilidad":150,"alimentacion":120.5,"alojamiento":0,"otros":null,"depositado":true,"version":"5-350-123"}""", Web)!;
        Assert.Equal(9, dto.IdTecnico);
        Assert.Equal(120.5m, dto.Alimentacion);
        Assert.Null(dto.Otros);
        Assert.True(dto.Depositado);
        Assert.Equal("5-350-123", dto.Version);
    }
}
