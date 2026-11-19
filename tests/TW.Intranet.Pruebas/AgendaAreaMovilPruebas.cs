using System.Text.Json;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de la agenda: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class AgendaRepoFalso : IAgendaAreaMovilRepositorio
{
    public int Llamadas { get; private set; }
    public string? Desde { get; private set; }
    public ResolucionConflictoDatos? Resuelto { get; private set; }
    public (string Tipo, long IdTecnico, long IdOsA, long? IdOsB)? Consultado { get; private set; }

    public static AgendaConflictoDto Conflicto() =>
        new("solapamiento:9:860:861", "solapamiento", "Solapamiento horario", "Solapamiento: Juan Pérez el 28/10 de 10:00 a 12:00 (OS-0860 y OS-0861).", "2026-10-28", 9, "Juan Pérez", 860, "OS-0860", 861, "OS-0861", true, "directa");

    public Task<RespuestaDto<AgendaAreaDto>> ObtenerAsync(long idUsuario, string? desde, CancellationToken ct)
    {
        Llamadas++;
        Desde = desde;
        var servicio = new AgendaServicioDto(860, 31, "OS-0860", "OS", "0860", "Molinos del Sur", "10:00", "13:00", "Mantenimiento", "conflicto", true);
        var dia = new AgendaDiaDto("2026-10-28", 11m, "sobrecarga", true, [servicio]);
        var tecnico = new AgendaTecnicoDto(9, "Juan Pérez", "Juan P.", "JP", [dia], 11m, 23, "baja");
        return Task.FromResult(new RespuestaDto<AgendaAreaDto>(2, "OK", new AgendaAreaDto("2026-10-26", "2026-10-30", new AgendaKpisDto(1, 2, 1, "10:46", 30), [tecnico], [Conflicto()])));
    }

    public Task<RespuestaDto<AgendaConflictoDetalleDto>> ObtenerConflictoAsync(long idUsuario, string tipo, long idTecnico, long idOsA, long? idOsB, CancellationToken ct)
    {
        Llamadas++;
        Consultado = (tipo, idTecnico, idOsA, idOsB);
        var servicios = new List<AgendaConflictoServicioDto>
        {
            new(860, 31, "OS-0860", "OS", "Molinos del Sur", "2026-10-28", "10:00", "13:00", "Mantenimiento", false),
            new(861, 32, "OS-0861", "OS", "Aceros del Pacífico", "2026-10-28", "09:00", "12:00", "Calibración", true),
        };
        return Task.FromResult(new RespuestaDto<AgendaConflictoDetalleDto>(2, "OK",
            new AgendaConflictoDetalleDto(Conflicto(), servicios, new TecnicoSugeridoDto(14, "Miguel Torres", "carga 50 % · SSOMA conforme"), [new OpcionAgendaDto(7, "Imprevisto operativo")], "directa",
                                          "Solapamiento horario de Juan Pérez el 28/10/2026.")));
    }

    public Task<RespuestaDto<ResolucionConflictoAgendaDto>> ResolverAsync(long idUsuario, ResolucionConflictoDatos datos, CancellationToken ct)
    {
        Llamadas++;
        Resuelto = datos;
        return Task.FromResult(new RespuestaDto<ResolucionConflictoAgendaDto>(2, "Programación actualizada.", new ResolucionConflictoAgendaDto("directa", "Programación actualizada.")));
    }
}

/// <summary>HU-37 agenda y carga del área desde la app: validación de la semana y de la resolución, delegación al SP (las reglas de alcance, permisos, cruces y SSOMA las valida el procedimiento).</summary>
public class AgendaAreaMovilPruebas
{
    private static readonly DateOnly Hoy = new(2026, 11, 18);   // miércoles; su lunes es el 16/11

    // ── Semana (desde) ──────────────────────────────────────────────────────

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Sin_fecha_es_la_semana_actual(string? desde)
    {
        var v = ValidacionAgendaAreaMovil.NormalizarDesde(desde, Hoy);
        Assert.Null(v.Error);
        Assert.Null(v.Desde);
    }

    [Theory]
    [InlineData("2026-11-16", "2026-11-16")]   // lunes
    [InlineData("2026-11-18", "2026-11-16")]   // miércoles
    [InlineData("2026-11-22", "2026-11-16")]   // domingo
    [InlineData("2026-11-23", "2026-11-23")]   // lunes siguiente
    [InlineData(" 2026-11-20 ", "2026-11-16")]
    public void Cualquier_fecha_se_normaliza_al_lunes_de_su_semana(string desde, string esperado)
    {
        var v = ValidacionAgendaAreaMovil.NormalizarDesde(desde, Hoy);
        Assert.Null(v.Error);
        Assert.Equal(esperado, v.Desde);
    }

    [Theory]
    [InlineData("2026-13-01")]
    [InlineData("18/11/2026")]
    [InlineData("2026-11")]
    [InlineData("mañana")]
    [InlineData("2026-11-18'; DROP TABLE usuario;--")]
    public void Fecha_con_formato_invalido_se_rechaza(string desde)
        => Assert.Equal(ValidacionAgendaAreaMovil.MensajeFechaInvalida, ValidacionAgendaAreaMovil.NormalizarDesde(desde, Hoy).Error);

    [Fact]
    public void El_rango_es_de_26_semanas_antes_o_despues_de_la_actual()
    {
        // Lunes actual 2026-11-16: +26 semanas = 2027-05-17 (válido); +27 = 2027-05-24 (fuera)
        Assert.Null(ValidacionAgendaAreaMovil.NormalizarDesde("2027-05-17", Hoy).Error);
        Assert.Equal(ValidacionAgendaAreaMovil.MensajeFueraDeRango, ValidacionAgendaAreaMovil.NormalizarDesde("2027-05-24", Hoy).Error);
        Assert.Null(ValidacionAgendaAreaMovil.NormalizarDesde("2026-05-18", Hoy).Error);    // -26 semanas
        Assert.Equal(ValidacionAgendaAreaMovil.MensajeFueraDeRango, ValidacionAgendaAreaMovil.NormalizarDesde("2026-05-11", Hoy).Error);
    }

    [Fact]
    public void Lunes_de_un_domingo_es_el_lunes_anterior()
        => Assert.Equal(new DateOnly(2026, 11, 16), ValidacionAgendaAreaMovil.Lunes(new DateOnly(2026, 11, 22)));

    // ── Detalle del conflicto ───────────────────────────────────────────────

    [Fact]
    public void Cruce_exige_las_dos_ordenes_distintas()
    {
        Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarConflicto("solapamiento", 9, 860, null).Error);
        Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarConflicto("extension_duracion", 9, 860, 860).Error);
        var ok = ValidacionAgendaAreaMovil.NormalizarConflicto(" Solapamiento ", 9, 860, 861);
        Assert.Null(ok.Error);
        Assert.Equal(("solapamiento", 9L, 860L, (long?)861), (ok.Tipo, ok.IdTecnico, ok.IdOsA, ok.IdOsB));
    }

    [Theory]
    [InlineData("baja")]
    [InlineData("ssoma_vencido")]
    public void Baja_y_ssoma_ignoran_la_segunda_orden(string tipo)
    {
        var v = ValidacionAgendaAreaMovil.NormalizarConflicto(tipo, 9, 860, 999);
        Assert.Null(v.Error);
        Assert.Null(v.IdOsB);
    }

    [Theory]
    [InlineData(null, 9L, 860L)]
    [InlineData("otro", 9L, 860L)]
    [InlineData("baja", null, 860L)]
    [InlineData("baja", 0L, 860L)]
    [InlineData("baja", 9L, null)]
    [InlineData("baja", 9L, -1L)]
    public void Conflicto_con_datos_invalidos_se_rechaza(string? tipo, long? idTecnico, long? idOsA)
        => Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarConflicto(tipo, idTecnico, idOsA, null).Error);

    // ── Resolver ────────────────────────────────────────────────────────────

    private static ResolverConflictoAgendaDto Reprogramar(string? fecha = "2026-11-25", string? ini = "14:00", string? fin = "16:00") =>
        new("solapamiento", 9, 860, 861, "reprogramar", 861, null, fecha, ini, fin, 7, "  Cliente pidió otro horario  ");

    private static ResolverConflictoAgendaDto Reasignar(long? nuevo = 14) =>
        new("solapamiento", 9, 860, 861, "REASIGNAR", 861, nuevo, null, null, null, null, null);

    [Fact]
    public void Reprogramar_valido_se_normaliza()
    {
        var v = ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar(), Hoy);
        Assert.Null(v.Error);
        var d = v.Datos!;
        Assert.Equal(("solapamiento", 9L, 860L, (long?)861, "reprogramar", (long?)861), (d.Tipo, d.IdTecnico, d.IdOsA, d.IdOsB, d.Opcion, d.IdOsObjetivo));
        Assert.Equal(new DateOnly(2026, 11, 25), d.Fecha);
        Assert.Equal((new TimeOnly(14, 0), new TimeOnly(16, 0)), (d.HoraInicio, d.HoraFin));
        Assert.Equal(7, d.IdMotivo);
        Assert.Equal("Cliente pidió otro horario", d.Comentario);
        Assert.Null(d.IdNuevoTecnico);
    }

    [Fact]
    public void Reasignar_valido_se_normaliza_y_no_lleva_horario()
    {
        var v = ValidacionAgendaAreaMovil.NormalizarResolucion(Reasignar(), Hoy);
        Assert.Null(v.Error);
        var d = v.Datos!;
        Assert.Equal("reasignar", d.Opcion);
        Assert.Equal(14L, d.IdNuevoTecnico);
        Assert.Null(d.Fecha);
        Assert.Null(d.HoraInicio);
        Assert.Null(d.Comentario);
    }

    [Fact]
    public void Resolver_sin_cuerpo_se_rechaza()
        => Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(null, Hoy).Error);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("cancelar")]
    [InlineData("borrar")]
    public void Opcion_fuera_de_la_lista_se_rechaza(string? opcion)
        => Assert.Contains("reasignar o reprogramar", ValidacionAgendaAreaMovil.NormalizarResolucion(Reasignar() with { Opcion = opcion }, Hoy).Error!);

    [Theory]
    [InlineData(null)]
    [InlineData(0L)]
    [InlineData(9L)]   // el mismo técnico en conflicto
    public void Reasignar_exige_un_tecnico_nuevo_distinto(long? nuevo)
        => Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(Reasignar(nuevo), Hoy).Error);

    [Theory]
    [InlineData(null, "14:00", "16:00")]
    [InlineData("25/11/2026", "14:00", "16:00")]
    [InlineData("2026-11-25", null, "16:00")]
    [InlineData("2026-11-25", "14:00", null)]
    [InlineData("2026-11-25", "2 pm", "16:00")]
    [InlineData("2026-11-25", "25:00", "26:00")]
    [InlineData("2026-11-25", "16:00", "14:00")]   // fin antes del inicio
    [InlineData("2026-11-25", "14:00", "14:00")]   // sin duración
    [InlineData("2026-11-17", "14:00", "16:00")]   // fecha pasada
    public void Reprogramar_con_fecha_u_horas_invalidas_se_rechaza(string? fecha, string? ini, string? fin)
        => Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar(fecha, ini, fin), Hoy).Error);

    [Fact]
    public void Reprogramar_hoy_mismo_es_valido()
        => Assert.Null(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar("2026-11-18"), Hoy).Error);

    [Fact]
    public void Comentario_largo_o_con_caracteres_de_control_se_rechaza()
    {
        Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { Comentario = new string('x', 401) }, Hoy).Error);
        Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { Comentario = "hola\u0000mundo" }, Hoy).Error);
        Assert.Null(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { Comentario = new string('x', 400) }, Hoy).Error);
    }

    [Fact]
    public void La_orden_objetivo_debe_ser_una_del_conflicto_y_el_motivo_positivo()
    {
        Assert.Contains("no forma parte", ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { IdOsObjetivo = 999 }, Hoy).Error!);
        Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { IdOsObjetivo = 0 }, Hoy).Error);
        Assert.NotNull(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { IdMotivo = 0 }, Hoy).Error);
        Assert.Null(ValidacionAgendaAreaMovil.NormalizarResolucion(Reprogramar() with { IdOsObjetivo = null }, Hoy).Error);   // por defecto la orden A
    }

    // ── Casos de uso ────────────────────────────────────────────────────────

    [Fact]
    public async Task Sin_usuario_del_token_no_se_consulta_nada()
    {
        var repo = new AgendaRepoFalso();
        Assert.Equal(1, (await new ObtenerAgendaAreaMovilCasoDeUso(repo).EjecutarAsync(0, null)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerConflictoAgendaMovilCasoDeUso(repo).EjecutarAsync(0, "baja", 9, 860, null)).IdTipoMensaje);
        Assert.Equal(1, (await new ResolverConflictoAgendaMovilCasoDeUso(repo).EjecutarAsync(0, Reasignar())).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Agenda_con_fecha_invalida_no_llama_al_repositorio()
    {
        var repo = new AgendaRepoFalso();
        var r = await new ObtenerAgendaAreaMovilCasoDeUso(repo).EjecutarAsync(7, "ayer");
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(ValidacionAgendaAreaMovil.MensajeFechaInvalida, r.Mensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Agenda_pasa_el_lunes_normalizado_o_nulo()
    {
        var repo = new AgendaRepoFalso();
        var uc = new ObtenerAgendaAreaMovilCasoDeUso(repo);

        var hoy = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-5));
        var miercolesDeEstaSemana = ValidacionAgendaAreaMovil.Lunes(hoy).AddDays(2).ToString("yyyy-MM-dd");
        await uc.EjecutarAsync(7, miercolesDeEstaSemana);
        Assert.Equal(ValidacionAgendaAreaMovil.Lunes(hoy).ToString("yyyy-MM-dd"), repo.Desde);

        await uc.EjecutarAsync(7, "  ");
        Assert.Null(repo.Desde);
    }

    [Fact]
    public async Task Detalle_con_datos_invalidos_no_llama_y_con_validos_normaliza()
    {
        var repo = new AgendaRepoFalso();
        var uc = new ObtenerConflictoAgendaMovilCasoDeUso(repo);
        Assert.Equal(1, (await uc.EjecutarAsync(7, "solapamiento", 9, 860, null)).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);

        var r = await uc.EjecutarAsync(7, "Solapamiento", 9, 860, 861);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(("solapamiento", 9L, 860L, (long?)861), repo.Consultado);
    }

    [Fact]
    public async Task Resolver_invalido_no_llama_y_valido_pasa_los_datos_normalizados()
    {
        var repo = new AgendaRepoFalso();
        var uc = new ResolverConflictoAgendaMovilCasoDeUso(repo);
        Assert.Equal(1, (await uc.EjecutarAsync(7, Reprogramar("2026-11-25", "16:00", "14:00") with { Fecha = "2999-01-01" })).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);

        var fecha = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-5)).AddDays(7).ToString("yyyy-MM-dd");
        var r = await uc.EjecutarAsync(7, Reprogramar(fecha));
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal("directa", r.Datos!.Modo);
        Assert.Equal(("reprogramar", 861L, 7), (repo.Resuelto!.Opcion, repo.Resuelto.IdOsObjetivo ?? 0, repo.Resuelto.IdMotivo ?? 0));
    }

    // ── Serialización: los nombres que consume la app ───────────────────────

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task Agenda_serializa_los_nombres_acordados_en_camelCase()
    {
        var r = await new AgendaRepoFalso().ObtenerAsync(7, null, default);
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(r.Datos, Web));
        var raiz = doc.RootElement;
        foreach (var k in new[] { "desde", "hasta", "kpis", "tecnicos", "conflictos" }) Assert.True(raiz.TryGetProperty(k, out _), k);
        foreach (var k in new[] { "conflictos", "servicios", "sobrecargados", "actualizado", "refrescoSegundos" }) Assert.True(raiz.GetProperty("kpis").TryGetProperty(k, out _), k);
        var t = raiz.GetProperty("tecnicos")[0];
        foreach (var k in new[] { "idUsuario", "nombre", "nombreCorto", "iniciales", "dias", "horasSemana", "utilizacionPct", "nivel" }) Assert.True(t.TryGetProperty(k, out _), k);
        var d = t.GetProperty("dias")[0];
        foreach (var k in new[] { "fecha", "horas", "nivel", "conflicto", "servicios" }) Assert.True(d.TryGetProperty(k, out _), k);
        foreach (var k in new[] { "idOs", "idProgramacion", "numeroOs", "tipo", "codigo", "cliente", "horaInicio", "horaFin", "tipoServicio", "estado", "conflicto" })
            Assert.True(d.GetProperty("servicios")[0].TryGetProperty(k, out _), k);
        foreach (var k in new[] { "clave", "tipo", "titulo", "detalle", "fecha", "idTecnico", "tecnico", "idOsA", "numeroOsA", "idOsB", "numeroOsB", "puedeResolver", "modo" })
            Assert.True(raiz.GetProperty("conflictos")[0].TryGetProperty(k, out _), k);
    }

    [Fact]
    public async Task Detalle_del_conflicto_serializa_los_nombres_acordados_en_camelCase()
    {
        var r = await new AgendaRepoFalso().ObtenerConflictoAsync(7, "solapamiento", 9, 860, 861, default);
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(r.Datos, Web));
        var raiz = doc.RootElement;
        foreach (var k in new[] { "conflicto", "servicios", "sugerido", "motivos", "modo", "motivoSugerido" }) Assert.True(raiz.TryGetProperty(k, out _), k);
        foreach (var k in new[] { "idOs", "idProgramacion", "numeroOs", "tipo", "cliente", "fecha", "horaInicio", "horaFin", "tipoServicio", "objetivo" })
            Assert.True(raiz.GetProperty("servicios")[0].TryGetProperty(k, out _), k);
        foreach (var k in new[] { "idUsuario", "nombre", "detalle" }) Assert.True(raiz.GetProperty("sugerido").TryGetProperty(k, out _), k);
        foreach (var k in new[] { "id", "nombre" }) Assert.True(raiz.GetProperty("motivos")[0].TryGetProperty(k, out _), k);
    }

    [Fact]
    public void Resolver_se_deserializa_con_los_nombres_que_envia_la_app()
    {
        const string json = """
            {"tipo":"solapamiento","idTecnico":9,"idOsA":860,"idOsB":861,"opcion":"reprogramar","idOsObjetivo":861,"idNuevoTecnico":null,
             "fecha":"2026-11-25","horaInicio":"14:00","horaFin":"16:00","idMotivo":7,"comentario":"ok"}
            """;
        var d = JsonSerializer.Deserialize<ResolverConflictoAgendaDto>(json, Web)!;
        Assert.Equal(("solapamiento", 9L, 860L, 861L, "reprogramar"), (d.Tipo, d.IdTecnico, d.IdOsA, d.IdOsB, d.Opcion));
        Assert.Equal(("2026-11-25", "14:00", "16:00", 7, "ok"), (d.Fecha, d.HoraInicio, d.HoraFin, d.IdMotivo, d.Comentario));
    }
}
