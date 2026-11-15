using System.Text.Json;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Pruebas;

/// <summary>HU-27 rendir gastos desde la app y HU-31 bandeja del jefe: validación de entrada, fotos y limpieza de archivos.</summary>
public class GastosMovilPruebas
{
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    private static readonly byte[] Png  = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];

    private static PeticionGastoMovilDto Viatico(decimal monto = 50m, params (long Linea, decimal Monto)[] reparto) => new()
    {
        IdCliente  = Guid.NewGuid().ToString(),
        Origen     = "viatico",
        IdOs       = 10,
        Monto      = monto,
        FechaGasto = "2026-11-12",
        Reparto    = (reparto.Length == 0 ? [(1L, monto)] : reparto).Select(x => new RepartoGastoEntradaDto { IdViaticoLinea = x.Linea, Monto = x.Monto }).ToList(),
    };

    private static string Json(PeticionGastoMovilDto d) => JsonSerializer.Serialize(d, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private static List<(Stream, long)> Fotos(params byte[][] archivos) => archivos.Select(a => ((Stream)new MemoryStream(a), (long)a.Length)).ToList();

    // ── Normalizar ──────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Gasto_nuevo_exige_idCliente_guid()
    {
        var d = Viatico(); d.IdCliente = "no-es-guid";
        Assert.NotNull(EntradaGastoMovil.Normalizar(0, d, 1).Error);
    }

    [Fact]
    public void Origen_de_lista_cerrada()
    {
        var d = Viatico(); d.Origen = "regalo";
        Assert.NotNull(EntradaGastoMovil.Normalizar(0, d, 1).Error);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    [InlineData(10.555)]
    public void Monto_mayor_que_cero_y_con_dos_decimales(double monto)
    {
        var d = Viatico(); d.Monto = (decimal)monto; d.Reparto = [new() { IdViaticoLinea = 1, Monto = (decimal)monto }];
        Assert.NotNull(EntradaGastoMovil.Normalizar(0, d, 1).Error);
    }

    [Fact]
    public void Reparto_debe_sumar_exacto_el_monto()
        => Assert.Contains("suma", EntradaGastoMovil.Normalizar(0, Viatico(50m, (1, 20m), (2, 20m)), 1).Error);

    [Fact]
    public void Reparto_sin_lineas_repetidas()
        => Assert.NotNull(EntradaGastoMovil.Normalizar(0, Viatico(40m, (1, 20m), (1, 20m)), 1).Error);

    [Fact]
    public void Reembolso_no_lleva_reparto_y_exige_concepto()
    {
        var d = Viatico(); d.Origen = "reembolso"; d.IdConcepto = 3;
        Assert.NotNull(EntradaGastoMovil.Normalizar(0, d, 1).Error);
        d.Reparto = null; d.IdConcepto = null;
        Assert.NotNull(EntradaGastoMovil.Normalizar(0, d, 1).Error);
        d.IdConcepto = 3;
        Assert.Null(EntradaGastoMovil.Normalizar(0, d, 1).Error);
    }

    [Fact]
    public void Sin_fotos_exige_motivo()
    {
        var d = Viatico();
        Assert.NotNull(EntradaGastoMovil.Normalizar(0, d, 0).Error);
        d.MotivoSinFoto = "El taxi no entregó boleta";
        Assert.Null(EntradaGastoMovil.Normalizar(0, d, 0).Error);
    }

    [Fact]
    public void Maximo_cinco_fotos_contando_las_conservadas()
    {
        var d = Viatico(); d.FotosConservar = [1, 2, 3];
        Assert.NotNull(EntradaGastoMovil.Normalizar(7, d, 3).Error);
        Assert.Null(EntradaGastoMovil.Normalizar(7, d, 2).Error);
    }

    [Fact]
    public void Gasto_valido_se_normaliza()
    {
        var (c, e) = EntradaGastoMovil.Normalizar(0, Viatico(50m, (1, 30m), (2, 20m)), 1);
        Assert.Null(e);
        Assert.Equal("viatico", c!.Origen);
        Assert.Equal(50m, c.Monto);
        Assert.Contains("idViaticoLinea", c.RepartoJson);
    }

    // ── Caso de uso ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public async Task Foto_que_no_es_jpeg_se_rechaza_sin_guardar_nada()
    {
        var repo = new GastosMovilRepoFalso(); var almacen = new AlmacenFalso();
        var r = await new RendirGastoMovilCasoDeUso(repo, new LectorIaFalso(null), almacen).EjecutarAsync(5, 0, Json(Viatico()), null, Fotos(Png));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
        Assert.Empty(almacen.Archivos);
    }

    [Fact]
    public async Task Foto_de_mas_de_5_mb_se_rechaza()
    {
        var repo = new GastosMovilRepoFalso();
        var grande = new byte[5 * 1024 * 1024 + 1]; Jpeg.CopyTo(grande, 0);
        var r = await new RendirGastoMovilCasoDeUso(repo, new LectorIaFalso(null), new AlmacenFalso()).EjecutarAsync(5, 0, Json(Viatico()), null, Fotos(grande));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Si_el_sp_no_guarda_se_borran_las_fotos()
    {
        var repo = new GastosMovilRepoFalso { RespuestaRendir = new(1, "No estás asignado a este servicio.") };
        var almacen = new AlmacenFalso();
        var r = await new RendirGastoMovilCasoDeUso(repo, new LectorIaFalso(null), almacen).EjecutarAsync(5, 0, Json(Viatico()), null, Fotos(Jpeg, Jpeg));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(2, almacen.Eliminados.Count);
        Assert.Empty(almacen.Archivos);
    }

    [Fact]
    public async Task Reintento_duplicado_borra_las_fotos_nuevas()
    {
        var repo = new GastosMovilRepoFalso { RespuestaRendir = new(2, "El gasto ya estaba registrado.", new(10, "GS-000010", "pendiente", true, [])) };
        var almacen = new AlmacenFalso();
        var r = await new RendirGastoMovilCasoDeUso(repo, new LectorIaFalso(null), almacen).EjecutarAsync(5, 0, Json(Viatico()), null, Fotos(Jpeg));
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Single(almacen.Eliminados);
    }

    [Fact]
    public async Task Lectura_ia_marca_si_coincide_con_el_monto()
    {
        var repo = new GastosMovilRepoFalso();
        await new RendirGastoMovilCasoDeUso(repo, new LectorIaFalso(50.02m), new AlmacenFalso()).EjecutarAsync(5, 0, Json(Viatico(50m)), null, Fotos(Jpeg));
        Assert.Equal(50.02m, repo.UltimoComando!.MontoIa);
        Assert.True(repo.UltimoComando.CoincideIa);

        var repo2 = new GastosMovilRepoFalso();
        await new RendirGastoMovilCasoDeUso(repo2, new LectorIaFalso(80m), new AlmacenFalso()).EjecutarAsync(5, 0, Json(Viatico(50m)), null, Fotos(Jpeg));
        Assert.False(repo2.UltimoComando!.CoincideIa);
    }

    [Fact]
    public async Task Las_rutas_las_genera_el_servidor()
    {
        var repo = new GastosMovilRepoFalso();
        await new RendirGastoMovilCasoDeUso(repo, new LectorIaFalso(null), new AlmacenFalso()).EjecutarAsync(5, 0, Json(Viatico()), null, Fotos(Jpeg));
        Assert.All(repo.UltimoComando!.FotosNuevas, ruta => Assert.Matches(@"^gastos/5/\d{14}_[0-9a-f]{32}\.jpg$", ruta));
    }

    // ── Bandeja del jefe ────────────────────────────────────────────────────────────────────

    [Fact]
    public async Task Rechazar_evidencia_exige_motivo_y_aprobar_no()
    {
        var repo = new GastosMovilRepoFalso();
        var uc = new ResolverAprobacionJefeMovilCasoDeUso(repo);
        Assert.Equal(1, (await uc.EjecutarAsync(1, "evidencia", 3, new ResolverAutorizacionSalidaDto(false, " "))).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
        Assert.Equal(2, (await uc.EjecutarAsync(1, "evidencia", 3, new ResolverAutorizacionSalidaDto(true, null))).IdTipoMensaje);
    }

    [Fact]
    public async Task Resolver_jefe_solo_evidencia_o_ensayo()
    {
        var repo = new GastosMovilRepoFalso();
        var r = await new ResolverAprobacionJefeMovilCasoDeUso(repo).EjecutarAsync(1, "salida", 3, new ResolverAutorizacionSalidaDto(true, "ok"));
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Theory]
    [InlineData("observar", null)]
    [InlineData("rechazar", "")]
    [InlineData("pagar", "ok")]
    public async Task Revisar_gasto_desde_la_app_valida_accion_y_comentario(string accion, string? comentario)
    {
        var repo = new GastosMovilRepoFalso();
        var r = await new RevisarGastoJefeMovilCasoDeUso(repo).EjecutarAsync(1, 20, new RevisarGastoDto { Accion = accion, Comentario = comentario });
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Archivo_de_aprobacion_no_sirve_enlaces_externos()
    {
        var repo = new GastosMovilRepoFalso { RutaArchivo = "https://malicioso.com/a.jpg" };
        var (contenido, _, _) = await new ObtenerArchivoAprobacionMovilCasoDeUso(repo, new AlmacenFalso()).EjecutarAsync(1, "gasto", 20, 1, false);
        Assert.Null(contenido);
    }

    [Fact]
    public void Bandeja_suma_los_tipos_nuevos()
    {
        var otros = new List<AprobacionMovilDto>
        {
            new("gasto", 20, "Gasto: Peaje S/ 12.00", "OS-000011", "Edwar", "Antamina", null, "2026-11-12", "12:00", true, DateTime.UtcNow),
            new("evidencia", 7, "Evidencia forzada: placa", "OS-000011", "Edwar", "Antamina", null, "2026-11-12", "12:00", false, DateTime.UtcNow),
        };
        var b = ObtenerAprobacionesMovilCasoDeUso.Armar([], [], otros, "2026-11-12");
        Assert.Equal(2, b.Total);
        Assert.Equal(1, b.Urgentes);
        Assert.Contains(b.Tipos, t => t.Tipo == "gasto" && t.Cantidad == 1);
        Assert.Contains(b.Tipos, t => t.Tipo == "evidencia" && t.Cantidad == 1);
        Assert.Equal("gasto", b.Items[0].Tipo);
    }
}
