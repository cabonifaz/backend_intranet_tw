using System.Text.Json;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de la revisión de informes: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class InformesRevisionRepoFalso : IInformesRevisionMovilRepositorio
{
    public int Llamadas { get; private set; }
    public string? Grupo { get; private set; }
    public string? Busqueda { get; private set; }
    public (string Motivo, string Secciones, string Instruccion, int Plazo)? Observado { get; private set; }
    public string? NotaAprobada { get; private set; }
    public RespuestaDto<ArchivoAprobacionMovilDto> RespuestaArchivo { get; set; } = new(2, "OK", new ArchivoAprobacionMovilDto("evidencias/1.jpg", "evidencias/1_cuadro.jpg", false));

    public Task<RespuestaDto<InformesRevisionDto>> ObtenerAsync(long idUsuario, string grupo, string? busqueda, CancellationToken ct)
    {
        Llamadas++; Grupo = grupo; Busqueda = busqueda;
        return Task.FromResult(new RespuestaDto<InformesRevisionDto>(2, "OK", new InformesRevisionDto(new InformesRevisionKpisDto(0, 0, 0, 0, null, 30), [])));
    }

    public Task<RespuestaDto<InformeRevisionDetalleDto>> ObtenerDetalleAsync(long idUsuario, long idInforme, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(new RespuestaDto<InformeRevisionDetalleDto>(1, "sin datos"));
    }

    public Task<RespuestaDto<ArchivoAprobacionMovilDto>> ObtenerArchivoAsync(long idUsuario, long idInforme, long idEvidencia, CancellationToken ct)
    {
        Llamadas++;
        return Task.FromResult(RespuestaArchivo);
    }

    public Task<RespuestaDto<ObservacionInformeResultadoDto>> ObservarAsync(long idUsuario, long idInforme, string motivo, string secciones, string instruccion, int plazoHoras, CancellationToken ct)
    {
        Llamadas++; Observado = (motivo, secciones, instruccion, plazoHoras);
        return Task.FromResult(new RespuestaDto<ObservacionInformeResultadoDto>(2, "OK", new ObservacionInformeResultadoDto(5, "2026-11-19T12:00:00", 1)));
    }

    public Task<RespuestaDto<AprobacionInformeResultadoDto>> AprobarAsync(long idUsuario, long idInforme, string? nota, CancellationToken ct)
    {
        Llamadas++; NotaAprobada = nota;
        return Task.FromResult(new RespuestaDto<AprobacionInformeResultadoDto>(2, "OK", new AprobacionInformeResultadoDto(idInforme, "revisado")));
    }
}

/// <summary>HU-33 revisión de informes técnicos desde la app: validación de entrada y delegación al SP (las reglas de negocio las valida el procedimiento).</summary>
public class InformesRevisionMovilPruebas
{
    private static ObservarInformeDto Observacion() => new("evidencia_insuficiente", ["registro_fotografico", "cabecera"], "Tomar foto de la placa del indicador con el N/S.", 24);

    // ── Pestañas y búsqueda ─────────────────────────────────────────────────

    [Theory]
    [InlineData(null, "por_revisar")]
    [InlineData("", "por_revisar")]
    [InlineData("  EN_CORRECCION ", "en_correccion")]
    [InlineData("aprobados", "aprobados")]
    public void Grupo_valido_se_normaliza(string? entrada, string esperado)
        => Assert.Equal(esperado, ValidacionInformesRevisionMovil.NormalizarGrupo(entrada));

    [Theory]
    [InlineData("todos")]
    [InlineData("por_revisar; DROP TABLE informe_tecnico")]
    public void Grupo_fuera_de_la_lista_cerrada_se_rechaza(string entrada)
        => Assert.Null(ValidacionInformesRevisionMovil.NormalizarGrupo(entrada));

    [Fact]
    public async Task Lista_rechaza_grupo_invalido_sin_llamar_al_repositorio()
    {
        var repo = new InformesRevisionRepoFalso();
        var r = await new ObtenerInformesRevisionMovilCasoDeUso(repo).EjecutarAsync(7, "todos", null);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Lista_rechaza_busqueda_de_mas_de_80_caracteres()
    {
        var repo = new InformesRevisionRepoFalso();
        var r = await new ObtenerInformesRevisionMovilCasoDeUso(repo).EjecutarAsync(7, "por_revisar", new string('a', 81));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Lista_pasa_grupo_y_busqueda_normalizados()
    {
        var repo = new InformesRevisionRepoFalso();
        var r = await new ObtenerInformesRevisionMovilCasoDeUso(repo).EjecutarAsync(7, "  Aprobados", "  IT-0845 ");
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal("aprobados", repo.Grupo);
        Assert.Equal("IT-0845", repo.Busqueda);
    }

    [Fact]
    public async Task Sin_usuario_del_token_no_se_consulta_nada()
    {
        var repo = new InformesRevisionRepoFalso();
        Assert.Equal(1, (await new ObtenerInformesRevisionMovilCasoDeUso(repo).EjecutarAsync(0, null, null)).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerInformeRevisionMovilCasoDeUso(repo).EjecutarAsync(0, 5)).IdTipoMensaje);
        Assert.Equal(1, (await new ObservarInformeMovilCasoDeUso(repo).EjecutarAsync(0, 5, Observacion())).IdTipoMensaje);
        Assert.Equal(1, (await new AprobarInformeMovilCasoDeUso(repo).EjecutarAsync(0, 5, null)).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Detalle_con_id_invalido_se_rechaza()
    {
        var repo = new InformesRevisionRepoFalso();
        Assert.Equal(1, (await new ObtenerInformeRevisionMovilCasoDeUso(repo).EjecutarAsync(7, -3)).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    // ── Observar ────────────────────────────────────────────────────────────

    [Fact]
    public void Observacion_valida_se_normaliza()
    {
        var d = Observacion() with { Motivo = "  Evidencia_Insuficiente ", Secciones = [" Registro_Fotografico", "cabecera "], Instruccion = "  Tomar foto de la placa del indicador.  " };
        var v = ValidacionInformesRevisionMovil.NormalizarObservacion(d);
        Assert.Null(v.Error);
        Assert.Equal("evidencia_insuficiente", v.Motivo);
        Assert.Equal("registro_fotografico,cabecera", v.Secciones);
        Assert.Equal("Tomar foto de la placa del indicador.", v.Instruccion);
        Assert.Equal(24, v.PlazoHoras);
    }

    [Fact]
    public void Observacion_nula_o_sin_motivo_se_rechaza()
    {
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(null).Error);
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Motivo = null }).Error);
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Motivo = "mal motivo'; --" }).Error);
    }

    [Fact]
    public void Exige_al_menos_una_seccion_sin_repetidas_y_con_formato_valido()
    {
        Assert.Contains("sección", ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Secciones = null }).Error);
        Assert.Contains("sección", ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Secciones = [] }).Error);
        Assert.Contains("repetidas", ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Secciones = ["cabecera", "CABECERA"] }).Error);
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Secciones = ["cabecera,firmas"] }).Error);
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Secciones = [""] }).Error);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("corto")]
    public void La_instruccion_necesita_al_menos_10_caracteres(string texto)
        => Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Instruccion = texto }).Error);

    [Fact]
    public void La_instruccion_admite_hasta_1000_caracteres_y_sin_caracteres_de_control()
    {
        Assert.Null(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Instruccion = new string('a', 1000) }).Error);
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Instruccion = new string('a', 1001) }).Error);
        Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Instruccion = "texto con control \u0007 invalido" }).Error);
        Assert.Null(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { Instruccion = "línea uno\nlínea dos del texto" }).Error);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(0)]
    [InlineData(-4)]
    [InlineData(721)]
    public void El_plazo_debe_ser_positivo_y_razonable(int? horas)
        => Assert.NotNull(ValidacionInformesRevisionMovil.NormalizarObservacion(Observacion() with { PlazoHoras = horas }).Error);

    [Fact]
    public async Task Observar_valido_llega_al_repositorio_con_los_datos_normalizados()
    {
        var repo = new InformesRevisionRepoFalso();
        var r = await new ObservarInformeMovilCasoDeUso(repo).EjecutarAsync(7, 12, Observacion());
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(("evidencia_insuficiente", "registro_fotografico,cabecera", "Tomar foto de la placa del indicador con el N/S.", 24), repo.Observado);
    }

    [Fact]
    public async Task Observar_invalido_no_llega_al_repositorio()
    {
        var repo = new InformesRevisionRepoFalso();
        var r = await new ObservarInformeMovilCasoDeUso(repo).EjecutarAsync(7, 12, Observacion() with { Secciones = [] });
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Null(repo.Observado);
        Assert.Equal(1, (await new ObservarInformeMovilCasoDeUso(repo).EjecutarAsync(7, 0, Observacion())).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    // ── Aprobar ─────────────────────────────────────────────────────────────

    [Fact]
    public async Task Aprobar_sin_nota_es_valido_y_la_nota_se_recorta()
    {
        var repo = new InformesRevisionRepoFalso();
        Assert.Equal(2, (await new AprobarInformeMovilCasoDeUso(repo).EjecutarAsync(7, 12, null)).IdTipoMensaje);
        Assert.Null(repo.NotaAprobada);
        Assert.Equal(2, (await new AprobarInformeMovilCasoDeUso(repo).EjecutarAsync(7, 12, new AprobarInformeDto("  Todo conforme  "))).IdTipoMensaje);
        Assert.Equal("Todo conforme", repo.NotaAprobada);
    }

    [Fact]
    public async Task Aprobar_con_nota_de_mas_de_500_caracteres_se_rechaza()
    {
        var repo = new InformesRevisionRepoFalso();
        var r = await new AprobarInformeMovilCasoDeUso(repo).EjecutarAsync(7, 12, new AprobarInformeDto(new string('x', 501)));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    // ── Detalle ampliado (datos, ensayos, procedimiento, observaciones, recomendaciones) ────────────────

    private static InformeRevisionCabeceraDto Cabecera() =>
        new(12, "0845-2026", null, "OS-000014", "Antamina", null, null, null, null, null, null, null, "por_revisar", false, 3, true, true, null, null, null, null);

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    [Fact]
    public void Detalle_ampliado_serializa_los_nombres_acordados_en_camelCase()
    {
        var detalle = new InformeRevisionDetalleDto(Cabecera(), [], [new EvidenciaInformeDto(3, "Placa del equipo", true, "placa ilegible", false, "rechazada", "Placa", "2026-11-18T10:30:00", "placa")],
            null, [], [], [],
            new InformeDatosRevisionDto(2, "Balanza", "Mettler", "X1", "08:00", "10:30", 150, "Rosa Quispe", "PR-1", "2026-11-18T11:00:00", "dentro", 0.5m, 0.3m, "Texto", "operativo"),
            [new EnsayoRevisionDto("pesaje", 1, "P1", null, 100m, 100.1m, 0.1m, 0.5m, "conforme")],
            [new PasoRevisionDto(1, "Limpieza", true)],
            [new TextoRevisionDto("OBS-01 · Celda", "Deriva")],
            [new TextoRevisionDto("REC-01 · Cambiar celda", null)]);

        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(detalle, Web));
        var raiz = doc.RootElement;
        Assert.Equal(2, raiz.GetProperty("datos").GetProperty("version").GetInt32());
        Assert.Equal("dentro", raiz.GetProperty("datos").GetProperty("resultadoGlobal").GetString());
        Assert.Equal(0.5m, raiz.GetProperty("datos").GetProperty("toleranciaPesaje").GetDecimal());
        Assert.Equal("operativo", raiz.GetProperty("datos").GetProperty("estadoEquipoFinal").GetString());
        Assert.Equal("P1", raiz.GetProperty("ensayos")[0].GetProperty("punto").GetString());
        Assert.Equal("conforme", raiz.GetProperty("ensayos")[0].GetProperty("resultado").GetString());
        Assert.True(raiz.GetProperty("procedimiento")[0].GetProperty("realizado").GetBoolean());
        Assert.Equal("Deriva", raiz.GetProperty("observaciones")[0].GetProperty("detalle").GetString());
        Assert.Equal(JsonValueKind.Null, raiz.GetProperty("recomendaciones")[0].GetProperty("detalle").ValueKind);
        var ev = raiz.GetProperty("evidencias")[0];
        Assert.Equal("Placa", ev.GetProperty("descripcion").GetString());
        Assert.Equal("2026-11-18T10:30:00", ev.GetProperty("tomadaEn").GetString());
        Assert.Equal("placa", ev.GetProperty("etapa").GetString());
    }

    [Fact]
    public void Los_campos_nuevos_del_detalle_son_opcionales()
    {
        var detalle = new InformeRevisionDetalleDto(Cabecera(), [], [new EvidenciaInformeDto(3, "Inicial", false, null, false, null)], null, [], [], []);
        Assert.Null(detalle.Datos);
        Assert.Null(detalle.Ensayos);
        Assert.Null(detalle.Evidencias[0].Descripcion);
        Assert.Null(detalle.Evidencias[0].TomadaEn);
        Assert.Null(detalle.Evidencias[0].Etapa);
    }

    // ── Archivo de la evidencia ─────────────────────────────────────────────

    [Fact]
    public async Task Archivo_devuelve_la_foto_o_la_miniatura_segun_cuadro()
    {
        var almacen = new AlmacenFalso();
        almacen.Archivos["evidencias/1.jpg"] = [1, 2, 3];
        almacen.Archivos["evidencias/1_cuadro.jpg"] = [9, 9];
        var caso = new ObtenerArchivoEvidenciaInformeMovilCasoDeUso(new InformesRevisionRepoFalso(), almacen);

        var foto = await caso.EjecutarAsync(7, 12, 33, false);
        Assert.NotNull(foto.Contenido);
        Assert.Equal("image/jpeg", foto.Tipo);
        Assert.Equal(3, ((MemoryStream)foto.Contenido!).Length);

        var cuadro = await caso.EjecutarAsync(7, 12, 33, true);
        Assert.Equal(2, ((MemoryStream)cuadro.Contenido!).Length);
    }

    [Theory]
    [InlineData(0, 12, 33)]
    [InlineData(7, 0, 33)]
    [InlineData(7, 12, -1)]
    public async Task Archivo_con_ids_invalidos_no_consulta_nada(long usuario, long informe, long evidencia)
    {
        var repo = new InformesRevisionRepoFalso();
        var a = await new ObtenerArchivoEvidenciaInformeMovilCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(usuario, informe, evidencia, false);
        Assert.Null(a.Contenido);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Archivo_sin_alcance_responde_el_mensaje_del_sp_sin_abrir_el_almacen()
    {
        var repo = new InformesRevisionRepoFalso { RespuestaArchivo = new(1, "Foto no encontrada.") };
        var a = await new ObtenerArchivoEvidenciaInformeMovilCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(7, 12, 33, false);
        Assert.Null(a.Contenido);
        Assert.Equal("Foto no encontrada.", a.Mensaje);
    }

    [Theory]
    [InlineData("../secretos/clave.jpg")]
    [InlineData("https://externo.com/foto.jpg")]
    public async Task Archivo_rechaza_rutas_fuera_del_almacenamiento(string ruta)
    {
        var repo = new InformesRevisionRepoFalso { RespuestaArchivo = new(2, "OK", new ArchivoAprobacionMovilDto(ruta, null, false)) };
        var a = await new ObtenerArchivoEvidenciaInformeMovilCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(7, 12, 33, false);
        Assert.Null(a.Contenido);
    }
}
