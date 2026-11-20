using System.Text;
using System.Text.Json;
using QuestPDF.Infrastructure;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Adaptadores;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de la recepción de instrumentos: guarda lo que recibe y responde lo configurado.</summary>
internal sealed class RecepcionOmRepoFalso : IRecepcionOmMovilRepositorio
{
    public int Llamadas { get; private set; }
    public RespuestaDto<RegistroRecepcionOmMovilDto> RespuestaRegistrar { get; set; } = new(2, "Recepción registrada.", new RegistroRecepcionOmMovilDto(31, "conforme", false, 2, 0, 0));
    public RespuestaDto<FotoRecepcionOmMovilDto> RespuestaFoto { get; set; } = new(2, "Foto guardada.", new FotoRecepcionOmMovilDto(9, 1));
    public RespuestaDto<string> RespuestaQuitar { get; set; } = new(2, "Foto quitada.", "recepcion-om/1/2/x.jpg");
    public RespuestaDto<ConstanciaRecepcionOmDto> RespuestaConstancia { get; set; } = new(2, "Éxito.", PruebasRecepcionOm.Constancia());
    public RespuestaDto<string> RespuestaRutaFoto { get; set; } = new(1, "Foto no encontrada.");
    public RespuestaDto<string?> RespuestaGuardarConstancia { get; set; } = new(2, "Constancia guardada.", null);
    public (string Guia, string Medio, string Entrego, string? Cargo, string? Motivo, string Instrumentos, string Firma)? Registrado { get; private set; }
    public string? RutaFotoGuardada { get; private set; }
    public (string Ruta, bool Correo)? ConstanciaGuardada { get; private set; }
    public string? BusquedaRecibida { get; private set; }

    public Task<RespuestaDto<ListaRecepcionOmMovilDto>> ObtenerListaAsync(long idUsuario, string? busqueda, CancellationToken ct)
    { Llamadas++; BusquedaRecibida = busqueda; return Task.FromResult(new RespuestaDto<ListaRecepcionOmMovilDto>(2, "OK", new ListaRecepcionOmMovilDto([], []))); }

    public Task<RespuestaDto<DetalleRecepcionOmMovilDto>> ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<DetalleRecepcionOmMovilDto>(1, "No")); }

    public Task<RespuestaDto<FotoRecepcionOmMovilDto>> RegistrarFotoAsync(long idUsuario, long idOs, long idOsEquipo, string ruta, CancellationToken ct)
    { Llamadas++; RutaFotoGuardada = ruta; return Task.FromResult(RespuestaFoto); }

    public Task<RespuestaDto<string>> QuitarFotoAsync(long idUsuario, long idOs, long idOsEquipo, long idFoto, CancellationToken ct)
    { Llamadas++; return Task.FromResult(RespuestaQuitar); }

    public Task<RespuestaDto<List<FotoRecepcionOmMovilDto>>> ObtenerFotosAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<List<FotoRecepcionOmMovilDto>>(2, "OK", [])); }

    public Task<RespuestaDto<string>> ObtenerRutaFotoAsync(long idUsuario, long idFoto, CancellationToken ct)
    { Llamadas++; return Task.FromResult(RespuestaRutaFoto); }

    public Task<RespuestaDto<InstrumentoQrRecepcionOmMovilDto>> BuscarQrAsync(long idUsuario, long idOs, string texto, CancellationToken ct)
    { Llamadas++; return Task.FromResult(new RespuestaDto<InstrumentoQrRecepcionOmMovilDto>(2, "OK", new InstrumentoQrRecepcionOmMovilDto(5, "Balanza"))); }

    public Task<RespuestaDto<RegistroRecepcionOmMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, string numeroGuia, string medioEntrega, string entregoNombre, string? entregoCargo, string? motivoParcial,
        string instrumentosJson, string firmaJson, CancellationToken ct)
    {
        Llamadas++;
        Registrado = (numeroGuia, medioEntrega, entregoNombre, entregoCargo, motivoParcial, instrumentosJson, firmaJson);
        return Task.FromResult(RespuestaRegistrar);
    }

    public Task<RespuestaDto<ConstanciaRecepcionOmDto>> ObtenerConstanciaAsync(long idUsuario, long idRecepcion, CancellationToken ct)
    { Llamadas++; return Task.FromResult(RespuestaConstancia); }

    public Task<RespuestaDto<string?>> GuardarConstanciaAsync(long idUsuario, long idRecepcion, string ruta, bool correoEnviado, CancellationToken ct)
    { Llamadas++; ConstanciaGuardada = (ruta, correoEnviado); return Task.FromResult(RespuestaGuardarConstancia); }
}

internal sealed class GeneradorRecepcionFalso(bool falla = false) : IGeneradorConstanciaRecepcionOmPdf
{
    public int Llamadas { get; private set; }
    public byte[] Generar(ConstanciaRecepcionOmDto datos)
    {
        Llamadas++;
        if (falla) throw new InvalidOperationException("sin fuentes");
        return Encoding.ASCII.GetBytes("%PDF-recepcion");
    }
}

internal sealed class EnviadorCorreoFalso(bool ok) : IEnviadorCorreo
{
    public string Proveedor => "falso";
    public int Enviados { get; private set; }
    public MensajeCorreoDto? Ultimo { get; private set; }
    public Task<ResultadoEnvioCorreoDto> EnviarAsync(MensajeCorreoDto mensaje, CancellationToken ct)
    { Enviados++; Ultimo = mensaje; return Task.FromResult(new ResultadoEnvioCorreoDto(ok, "falso", ok ? "id" : null, ok ? null : "Sin servicio")); }
}

internal sealed class CorreoRepoFalso : ICorreoRepositorio
{
    public Task<RespuestaDto<object>> RegistrarEnvioAsync(string tipo, MensajeCorreoDto mensaje, string? entidadTipo, long? idEntidad, ResultadoEnvioCorreoDto resultado, long idUsuario, CancellationToken ct)
        => Task.FromResult(new RespuestaDto<object>(2, "OK"));

    public Task<RespuestaDto<DatosCredencialUsuarioDto>> RestablecerContrasenaTemporalAsync(long idUsuario, string passwordHash, long idEjecutor, CancellationToken ct)
        => throw new NotSupportedException();
}

internal static class PruebasRecepcionOm
{
    public static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

    /// <summary>Firma válida: una onda de 20 puntos.</summary>
    public static JsonElement Firma()
    {
        var puntos = Enumerable.Range(0, 20).Select(i => $"[{(0.05 + i * 0.045).ToString(System.Globalization.CultureInfo.InvariantCulture)},{(0.5 + 0.3 * Math.Sin(i / 2.0)).ToString(System.Globalization.CultureInfo.InvariantCulture)}]");
        return JsonDocument.Parse($"{{\"trazos\":[[{string.Join(",", puntos)}]]}}").RootElement.Clone();
    }

    public static InstrumentoPeticionRecepcionOmMovilDto Instrumento(long id = 5, string estado = "conforme", string obs = "Equipo en buen estado, sin golpes.", params string[] accesorios)
        => new(id, estado, obs, accesorios.ToList(), [1, 2, 3]);

    public static PeticionRecepcionOmMovilDto Peticion() => new("T001-004587", "cliente_taller", "Rosa Quispe", "Molinos del Sur S.A.C.", null, [Instrumento(5), Instrumento(6, "observado", "Burbuja de nivel desplazada; protector ausente.", "caja_original")], Firma());

    public static ConstanciaRecepcionOmDto Constancia(bool parcial = false) => new(
        new CabeceraConstanciaRecepcionOmDto(31, "OM-000012", "Molinos del Sur S.A.C.", "Av. Industrial 123", "Carlos Mendoza", "c@x.com", "RQ-1",
            "T001-004587", "cliente_taller", "Rosa Quispe", "Molinos del Sur S.A.C.", "Juan Pérez", "2026-11-20 10:24", parcial ? "parcial" : "observado",
            parcial ? "El cliente lo enviará el 28/10 con otra guía." : null, Firma(), null, false, false),
        [new InstrumentoConstanciaRecepcionOmDto("Balanza analítica", "Ohaus", "PX224", "B-77120", "BAL-1", "observado", "Burbuja de nivel desplazada.", ["caja_original", "manual"], 3),
         new InstrumentoConstanciaRecepcionOmDto("Juego de pesas M1", "Zwiebel", null, null, null, "conforme", "Completo, en estuche.", [], 4)],
        parcial ? [new PendienteConstanciaRecepcionOmDto("Termohigrómetro", "Testo", "608-H1", "40221873", null)] : []);
}

/// <summary>HU-23 Recepción de instrumentos (OM): validación de la entrada, flujo de registro con constancia y correo, fotos, QR, descarga del PDF y el PDF real.</summary>
public class RecepcionOmMovilPruebas
{
    static RecepcionOmMovilPruebas() => QuestPDF.Settings.License = LicenseType.Community;

    private static (RegistrarRecepcionOmMovilCasoDeUso Caso, RecepcionOmRepoFalso Repo, GeneradorRecepcionFalso Pdf, AlmacenFalso Almacen, EnviadorCorreoFalso Correo) Armar(
        bool envioActivo = false, string? correoContacto = null, bool correoOk = true, bool pdfFalla = false)
    {
        var repo = new RecepcionOmRepoFalso();
        var datos = PruebasRecepcionOm.Constancia();
        repo.RespuestaConstancia = new(2, "OK", datos with { Cabecera = datos.Cabecera with { EnvioActivo = envioActivo, ContactoCorreo = correoContacto } });
        var pdf = new GeneradorRecepcionFalso(pdfFalla);
        var almacen = new AlmacenFalso();
        var correo = new EnviadorCorreoFalso(correoOk);
        var emitir = new EmitirConstanciaRecepcionOmMovilCasoDeUso(repo, pdf, almacen, new NotificadorCorreo(correo, new CorreoRepoFalso()));
        return (new RegistrarRecepcionOmMovilCasoDeUso(repo, emitir), repo, pdf, almacen, correo);
    }

    // ── Validación de la entrada ────────────────────────────────────────────

    [Fact]
    public void Peticion_valida_se_normaliza_y_arma_el_json_del_sp()
    {
        var p = PruebasRecepcionOm.Peticion() with { NumeroGuia = "  T001-004587 ", MedioEntrega = " Courier ", EntregoNombre = "  Rosa   Quispe " };
        var i = p.Instrumentos![1] with { Accesorios = ["Caja_Original", "caja_original", "MANUAL"] };
        p = p with { MedioEntrega = " COURIER ", Instrumentos = [p.Instrumentos[0], i] };

        var (cmd, error) = EntradaRecepcionOmMovil.Validar(p);

        Assert.Null(error);
        Assert.Equal("T001-004587", cmd!.NumeroGuia);
        Assert.Equal("courier", cmd.MedioEntrega);
        Assert.Equal("Rosa Quispe", cmd.EntregoNombre);
        using var doc = JsonDocument.Parse(cmd.InstrumentosJson);
        Assert.Equal(2, doc.RootElement.GetArrayLength());
        var segundo = doc.RootElement[1];
        Assert.Equal(6, segundo.GetProperty("idOsEquipo").GetInt64());
        Assert.Equal("observado", segundo.GetProperty("estadoFisico").GetString());
        Assert.Equal(["caja_original", "manual"], segundo.GetProperty("accesorios").EnumerateArray().Select(x => x.GetString()).ToArray());
        Assert.Equal(3, segundo.GetProperty("fotos").GetArrayLength());
        Assert.Contains("trazos", cmd.FirmaJson);
    }

    [Fact]
    public void Sin_cuerpo_se_rechaza() => Assert.NotNull(EntradaRecepcionOmMovil.Validar(null).Error);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("T1")]
    public void Guia_vacia_o_corta_se_rechaza(string? guia)
        => Assert.Contains("guía", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { NumeroGuia = guia }).Error);

    [Fact]
    public void Guia_de_mas_de_40_caracteres_se_rechaza()
    {
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { NumeroGuia = new string('G', 41) }).Error);
        Assert.Null(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { NumeroGuia = new string('G', 40) }).Error);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("paloma")]
    public void Medio_de_entrega_invalido_se_rechaza(string? medio)
        => Assert.Contains("medio de entrega", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { MedioEntrega = medio }).Error);

    [Theory]
    [InlineData("cliente_taller")]
    [InlineData("courier")]
    [InlineData("traslado_tw")]
    public void Los_tres_medios_son_validos(string medio)
        => Assert.Null(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { MedioEntrega = medio }).Error);

    [Fact]
    public void Quien_entrega_exige_de_3_a_120_caracteres_y_el_cargo_hasta_120()
    {
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { EntregoNombre = "Ro" }).Error);
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { EntregoNombre = new string('N', 121) }).Error);
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { EntregoCargo = new string('C', 121) }).Error);
        Assert.Null(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { EntregoCargo = null }).Error);
    }

    [Fact]
    public void El_motivo_parcial_admite_hasta_300_caracteres()
    {
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { MotivoParcial = new string('m', 301) }).Error);
        Assert.Null(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { MotivoParcial = new string('m', 300) }).Error);
    }

    [Fact]
    public void Sin_instrumentos_o_con_demasiados_se_rechaza()
    {
        Assert.Contains("al menos un instrumento", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = null }).Error);
        Assert.Contains("al menos un instrumento", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [] }).Error);
        var muchos = Enumerable.Range(1, 51).Select(n => PruebasRecepcionOm.Instrumento(n)).ToList();
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = muchos }).Error);
    }

    [Fact]
    public void Instrumento_repetido_o_con_id_invalido_se_rechaza()
    {
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [PruebasRecepcionOm.Instrumento(5), PruebasRecepcionOm.Instrumento(5)] }).Error);
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [PruebasRecepcionOm.Instrumento(0)] }).Error);
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [PruebasRecepcionOm.Instrumento(-3)] }).Error);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("roto")]
    public void Estado_fisico_es_obligatorio_y_solo_conforme_u_observado(string? estado)
        => Assert.Contains("estado físico", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [PruebasRecepcionOm.Instrumento(5, estado!)] }).Error);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("corto")]
    public void Observaciones_obligatorias_de_10_a_500_aunque_sea_conforme(string? obs)
    {
        var i = PruebasRecepcionOm.Instrumento(5, "conforme") with { Observaciones = obs };
        Assert.Contains("observaciones", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [i] }).Error);
    }

    [Fact]
    public void Observaciones_de_mas_de_500_caracteres_se_rechazan()
    {
        var i = PruebasRecepcionOm.Instrumento(5) with { Observaciones = new string('o', 501) };
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [i] }).Error);
        var ok = PruebasRecepcionOm.Instrumento(5) with { Observaciones = new string('o', 500) };
        Assert.Null(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [ok] }).Error);
    }

    [Fact]
    public void Accesorio_fuera_del_catalogo_se_rechaza()
    {
        var i = PruebasRecepcionOm.Instrumento(5, "conforme", "Equipo en buen estado, sin golpes.", "caja_original", "maletin");
        Assert.Contains("accesorio", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [i] }).Error);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(9)]
    public void Fotos_por_instrumento_de_3_a_8(int cantidad)
    {
        var i = PruebasRecepcionOm.Instrumento(5) with { Fotos = Enumerable.Range(1, cantidad).Select(n => (long)n).ToList() };
        Assert.Contains("fotos", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [i] }).Error);
    }

    [Theory]
    [InlineData(3)]
    [InlineData(8)]
    public void Tres_y_ocho_fotos_son_validas(int cantidad)
    {
        var i = PruebasRecepcionOm.Instrumento(5) with { Fotos = Enumerable.Range(1, cantidad).Select(n => (long)n).ToList() };
        Assert.Null(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [i] }).Error);
    }

    [Fact]
    public void Fotos_repetidas_o_con_id_invalido_se_rechazan()
    {
        var repetidas = PruebasRecepcionOm.Instrumento(5) with { Fotos = [1, 2, 2] };
        var invalida = PruebasRecepcionOm.Instrumento(5) with { Fotos = [1, 2, 0] };
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [repetidas] }).Error);
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Instrumentos = [invalida] }).Error);
    }

    [Fact]
    public void La_firma_de_quien_entrega_es_obligatoria_y_con_la_forma_de_la_hu17()
    {
        Assert.Contains("firma", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Firma = null }).Error);
        Assert.Contains("firma", EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Firma = JsonDocument.Parse("[1,2]").RootElement }).Error);
        // una rayita: pocos puntos y muy pequeña
        var rayita = JsonDocument.Parse("{\"trazos\":[[[0.1,0.1],[0.11,0.11]]]}").RootElement;
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Firma = rayita }).Error);
        // fuera de 0 a 1
        var fuera = JsonDocument.Parse("{\"trazos\":[[" + string.Join(",", Enumerable.Range(0, 20).Select(i => $"[{i},{i}]")) + "]]}").RootElement;
        Assert.NotNull(EntradaRecepcionOmMovil.Validar(PruebasRecepcionOm.Peticion() with { Firma = fuera }).Error);
    }

    [Fact]
    public void Busqueda_de_la_lista_hasta_80_caracteres()
    {
        Assert.Null(EntradaRecepcionOmMovil.ValidarBusqueda("  Molinos  ", out var limpia));
        Assert.Equal("Molinos", limpia);
        Assert.Null(EntradaRecepcionOmMovil.ValidarBusqueda("   ", out var vacia));
        Assert.Null(vacia);
        Assert.NotNull(EntradaRecepcionOmMovil.ValidarBusqueda(new string('b', 81), out _));
    }

    // ── Registrar la recepción ──────────────────────────────────────────────

    [Fact]
    public async Task Registrar_guarda_genera_la_constancia_y_devuelve_el_resultado()
    {
        var (caso, repo, pdf, almacen, correo) = Armar();

        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(31, r.Datos!.IdRecepcion);
        Assert.Equal("conforme", r.Datos.Estado);
        Assert.False(r.Datos.Parcial);
        Assert.Equal(2, r.Datos.InstrumentosRecibidos);
        Assert.False(r.Datos.CorreoEnviado);
        Assert.Equal("T001-004587", repo.Registrado!.Value.Guia);
        Assert.Equal(1, pdf.Llamadas);
        Assert.Single(almacen.Archivos);
        Assert.StartsWith("recepcion-om/constancias/", repo.ConstanciaGuardada!.Value.Ruta);
        Assert.Equal(0, correo.Enviados);
    }

    [Fact]
    public async Task Con_el_envio_activo_y_correo_del_contacto_se_envia_la_constancia()
    {
        var (caso, repo, _, _, correo) = Armar(envioActivo: true, correoContacto: "c@x.com");

        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());

        Assert.True(r.Datos!.CorreoEnviado);
        Assert.True(repo.ConstanciaGuardada!.Value.Correo);
        Assert.Equal(1, correo.Enviados);
        Assert.Equal("c@x.com", correo.Ultimo!.Para);
        Assert.Single(correo.Ultimo.Adjuntos!);
    }

    [Fact]
    public async Task Sin_correo_del_contacto_o_con_el_envio_desactivado_no_se_envia()
    {
        var (a, _, _, _, ca) = Armar(envioActivo: true, correoContacto: null);
        var (b, _, _, _, cb) = Armar(envioActivo: false, correoContacto: "c@x.com");
        await a.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());
        await b.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());
        Assert.Equal(0, ca.Enviados);
        Assert.Equal(0, cb.Enviados);
    }

    [Fact]
    public async Task Si_el_correo_falla_la_recepcion_igual_queda_registrada()
    {
        var (caso, repo, _, _, _) = Armar(envioActivo: true, correoContacto: "c@x.com", correoOk: false);

        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.False(r.Datos!.CorreoEnviado);
        Assert.False(repo.ConstanciaGuardada!.Value.Correo);
    }

    [Fact]
    public async Task Si_el_pdf_falla_la_recepcion_igual_queda_registrada_y_no_quedan_archivos()
    {
        var (caso, repo, _, almacen, _) = Armar(pdfFalla: true);

        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(31, r.Datos!.IdRecepcion);
        Assert.Empty(almacen.Archivos);
        Assert.Null(repo.ConstanciaGuardada);
    }

    [Fact]
    public async Task Si_el_sp_rechaza_la_recepcion_no_se_genera_constancia()
    {
        var (caso, repo, pdf, almacen, _) = Armar();
        repo.RespuestaRegistrar = new(1, "Falta recibir 1 instrumento: escribe el motivo.");

        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion());

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Contains("motivo", r.Mensaje);
        Assert.Equal(0, pdf.Llamadas);
        Assert.Empty(almacen.Archivos);
    }

    [Fact]
    public async Task Recepcion_parcial_devuelve_pendientes_y_el_estado_del_sp()
    {
        var (caso, repo, _, _, _) = Armar();
        repo.RespuestaRegistrar = new(2, "Recepción parcial registrada: faltan 1 instrumento.", new RegistroRecepcionOmMovilDto(40, "parcial", true, 2, 1, 3));

        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion() with { MotivoParcial = "El cliente lo enviará el 28/10 con otra guía." });

        Assert.True(r.Datos!.Parcial);
        Assert.Equal("parcial", r.Datos.Estado);
        Assert.Equal(1, r.Datos.InstrumentosPendientes);
        Assert.Equal("El cliente lo enviará el 28/10 con otra guía.", repo.Registrado!.Value.Motivo);
    }

    [Fact]
    public async Task Una_entrada_invalida_no_llega_al_sp()
    {
        var (caso, repo, _, _, _) = Armar();
        var r = await caso.EjecutarAsync(5, 1, PruebasRecepcionOm.Peticion() with { Firma = null });
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(5, 0)]
    public async Task Ids_no_validos_no_llegan_a_ningun_repositorio(long idUsuario, long idOs)
    {
        var (caso, repo, _, _, _) = Armar();
        var repoDos = new RecepcionOmRepoFalso();

        Assert.Equal(1, (await caso.EjecutarAsync(idUsuario, idOs, PruebasRecepcionOm.Peticion())).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerDetalleRecepcionOmMovilCasoDeUso(repoDos).EjecutarAsync(idUsuario, idOs)).IdTipoMensaje);
        Assert.Equal(1, (await new BuscarQrRecepcionOmMovilCasoDeUso(repoDos).EjecutarAsync(idUsuario, idOs, "ABC")).IdTipoMensaje);
        Assert.Equal(1, (await new ObtenerFotosRecepcionOmMovilCasoDeUso(repoDos).EjecutarAsync(idUsuario, idOs, 3)).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
        Assert.Equal(0, repoDos.Llamadas);
    }

    // ── Lista y QR ──────────────────────────────────────────────────────────

    [Fact]
    public async Task Lista_limpia_la_busqueda_y_rechaza_las_demasiado_largas()
    {
        var repo = new RecepcionOmRepoFalso();
        var caso = new ObtenerListaRecepcionOmMovilCasoDeUso(repo);

        Assert.Equal(2, (await caso.EjecutarAsync(5, "  Molinos ")).IdTipoMensaje);
        Assert.Equal("Molinos", repo.BusquedaRecibida);
        Assert.Equal(1, (await caso.EjecutarAsync(5, new string('x', 81))).IdTipoMensaje);
        Assert.Equal(1, (await caso.EjecutarAsync(0, null)).IdTipoMensaje);
        Assert.Equal(1, repo.Llamadas);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("   ")]
    public async Task Qr_vacio_no_llega_al_sp(string? texto)
    {
        var repo = new RecepcionOmRepoFalso();
        var r = await new BuscarQrRecepcionOmMovilCasoDeUso(repo).EjecutarAsync(5, 1, texto);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);
    }

    [Fact]
    public async Task Qr_de_mas_de_300_caracteres_se_rechaza_y_uno_normal_pasa()
    {
        var repo = new RecepcionOmRepoFalso();
        var caso = new BuscarQrRecepcionOmMovilCasoDeUso(repo);
        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, new string('Q', 301))).IdTipoMensaje);
        var r = await caso.EjecutarAsync(5, 1, "https://q.me-qr.com/abc123");
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(5, r.Datos!.IdOsEquipo);
    }

    // ── Fotos de recepción ──────────────────────────────────────────────────

    [Fact]
    public async Task Foto_jpeg_se_guarda_en_el_almacen_y_se_registra()
    {
        var repo = new RecepcionOmRepoFalso();
        var almacen = new AlmacenFalso();
        await using var s = new MemoryStream(PruebasRecepcionOm.Jpeg);

        var r = await new SubirFotoRecepcionOmMovilCasoDeUso(repo, almacen).EjecutarAsync(5, 1, 2, s, s.Length);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(9, r.Datos!.IdFoto);
        Assert.Single(almacen.Archivos);
        Assert.StartsWith("recepcion-om/1/2/foto_", repo.RutaFotoGuardada);
        Assert.EndsWith(".jpg", repo.RutaFotoGuardada);
    }

    [Fact]
    public async Task Foto_que_no_es_jpeg_vacia_o_demasiado_grande_se_rechaza_sin_tocar_nada()
    {
        var repo = new RecepcionOmRepoFalso();
        var almacen = new AlmacenFalso();
        var caso = new SubirFotoRecepcionOmMovilCasoDeUso(repo, almacen);

        await using var png = new MemoryStream([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, 2, png, png.Length)).IdTipoMensaje);
        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, 2, null, 0)).IdTipoMensaje);
        await using var grande = new MemoryStream(PruebasRecepcionOm.Jpeg);
        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, 2, grande, EntradaRecepcionOmMovil.TamanoMaximoFotoBytes + 1)).IdTipoMensaje);
        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, 0, grande, grande.Length)).IdTipoMensaje);

        Assert.Equal(0, repo.Llamadas);
        Assert.Empty(almacen.Archivos);
    }

    [Fact]
    public async Task Si_el_sp_rechaza_la_foto_no_queda_el_archivo()
    {
        var repo = new RecepcionOmRepoFalso { RespuestaFoto = new(1, "Un instrumento admite hasta 8 fotos de recepción.") };
        var almacen = new AlmacenFalso();
        await using var s = new MemoryStream(PruebasRecepcionOm.Jpeg);

        var r = await new SubirFotoRecepcionOmMovilCasoDeUso(repo, almacen).EjecutarAsync(5, 1, 2, s, s.Length);

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Empty(almacen.Archivos);
        Assert.Single(almacen.Eliminados);
    }

    [Fact]
    public async Task Quitar_una_foto_borra_su_archivo_y_los_ids_invalidos_no_llegan_al_sp()
    {
        var repo = new RecepcionOmRepoFalso();
        var almacen = new AlmacenFalso();
        almacen.Archivos["recepcion-om/1/2/x.jpg"] = [1];
        var caso = new QuitarFotoRecepcionOmMovilCasoDeUso(repo, almacen);

        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, 2, 0)).IdTipoMensaje);
        Assert.Equal(0, repo.Llamadas);

        var r = await caso.EjecutarAsync(5, 1, 2, 9);
        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Contains("recepcion-om/1/2/x.jpg", almacen.Eliminados);

        repo.RespuestaQuitar = new(1, "La foto no existe o ya forma parte de una recepción registrada.");
        Assert.Equal(1, (await caso.EjecutarAsync(5, 1, 2, 9)).IdTipoMensaje);
    }

    [Fact]
    public async Task Archivo_de_una_foto_solo_si_el_sp_lo_permite()
    {
        var repo = new RecepcionOmRepoFalso();
        var almacen = new AlmacenFalso();
        var caso = new ObtenerArchivoFotoRecepcionOmMovilCasoDeUso(repo, almacen);

        var (s1, _, m1) = await caso.EjecutarAsync(5, 9);
        Assert.Null(s1);
        Assert.Equal("Foto no encontrada.", m1);

        almacen.Archivos["recepcion-om/1/2/x.jpg"] = PruebasRecepcionOm.Jpeg;
        repo.RespuestaRutaFoto = new(2, "OK", "recepcion-om/1/2/x.jpg");
        var (s2, tipo, _) = await caso.EjecutarAsync(5, 9);
        Assert.NotNull(s2);
        Assert.Equal("image/jpeg", tipo);

        var (s3, _, _) = await caso.EjecutarAsync(5, 0);
        Assert.Null(s3);
    }

    // ── Constancia (descarga) ───────────────────────────────────────────────

    private static ObtenerConstanciaRecepcionOmMovilCasoDeUso ArmarDescarga(RecepcionOmRepoFalso repo, AlmacenFalso almacen, GeneradorRecepcionFalso pdf) =>
        new(repo, almacen, new EmitirConstanciaRecepcionOmMovilCasoDeUso(repo, pdf, almacen, new NotificadorCorreo(new EnviadorCorreoFalso(true), new CorreoRepoFalso())));

    [Fact]
    public async Task Descarga_devuelve_el_pdf_guardado_sin_regenerarlo()
    {
        var repo = new RecepcionOmRepoFalso();
        var datos = PruebasRecepcionOm.Constancia();
        repo.RespuestaConstancia = new(2, "OK", datos with { Cabecera = datos.Cabecera with { RutaConstancia = "recepcion-om/constancias/a.pdf" } });
        var almacen = new AlmacenFalso();
        almacen.Archivos["recepcion-om/constancias/a.pdf"] = Encoding.ASCII.GetBytes("%PDF-guardado");
        var pdf = new GeneradorRecepcionFalso();

        var r = await ArmarDescarga(repo, almacen, pdf).EjecutarAsync(5, 31);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal("%PDF-guardado", Encoding.ASCII.GetString(r.Datos!));
        Assert.Equal(0, pdf.Llamadas);
    }

    [Fact]
    public async Task Descarga_regenera_y_guarda_la_constancia_si_el_archivo_ya_no_esta()
    {
        var repo = new RecepcionOmRepoFalso();
        var datos = PruebasRecepcionOm.Constancia();
        repo.RespuestaConstancia = new(2, "OK", datos with { Cabecera = datos.Cabecera with { RutaConstancia = "recepcion-om/constancias/perdida.pdf" } });
        var almacen = new AlmacenFalso();
        var pdf = new GeneradorRecepcionFalso();

        var r = await ArmarDescarga(repo, almacen, pdf).EjecutarAsync(5, 31);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(1, pdf.Llamadas);
        Assert.Single(almacen.Archivos);
        Assert.NotNull(repo.ConstanciaGuardada);
    }

    [Fact]
    public async Task Descarga_sin_acceso_o_con_id_invalido_devuelve_la_regla()
    {
        var repo = new RecepcionOmRepoFalso { RespuestaConstancia = new(1, "Constancia no encontrada.") };
        var caso = ArmarDescarga(repo, new AlmacenFalso(), new GeneradorRecepcionFalso());

        var r = await caso.EjecutarAsync(5, 31);
        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Equal("Constancia no encontrada.", r.Mensaje);

        var antes = repo.Llamadas;
        Assert.Equal(1, (await caso.EjecutarAsync(5, 0)).IdTipoMensaje);
        Assert.Equal(antes, repo.Llamadas);
    }

    // ── PDF real y catálogos ────────────────────────────────────────────────

    [Fact]
    public void El_pdf_real_de_una_recepcion_con_observados_es_valido()
    {
        var bytes = new GeneradorConstanciaRecepcionOmPdf().Generar(PruebasRecepcionOm.Constancia());
        Assert.True(bytes.Length > 1000);
        Assert.Equal("%PDF", Encoding.ASCII.GetString(bytes, 0, 4));
    }

    [Fact]
    public void El_pdf_real_de_una_recepcion_parcial_con_pendientes_es_valido()
    {
        var bytes = new GeneradorConstanciaRecepcionOmPdf().Generar(PruebasRecepcionOm.Constancia(parcial: true));
        Assert.Equal("%PDF", Encoding.ASCII.GetString(bytes, 0, 4));
    }

    [Fact]
    public void El_pdf_real_soporta_datos_minimos_y_sin_firma()
    {
        var c = PruebasRecepcionOm.Constancia();
        var minimo = new ConstanciaRecepcionOmDto(
            c.Cabecera with { Cliente = null, Direccion = null, ContactoNombre = null, Recibio = null, FirmaTrazos = null, EntregoCargo = null }, [], []);
        var bytes = new GeneradorConstanciaRecepcionOmPdf().Generar(minimo);
        Assert.Equal("%PDF", Encoding.ASCII.GetString(bytes, 0, 4));
    }

    [Fact]
    public void Catalogos_con_las_etiquetas_de_la_app()
    {
        Assert.Equal(["caja_original", "adaptador_corriente", "protector_plato", "manual", "otro"], CatalogoRecepcionOm.Accesorios.Select(a => a.Codigo).ToArray());
        Assert.Equal("Adaptador de corriente", CatalogoRecepcionOm.EtiquetaAccesorio("adaptador_corriente"));
        Assert.Equal("Cliente en taller", CatalogoRecepcionOm.EtiquetaMedio("cliente_taller"));
        Assert.Equal("Traslado TW", CatalogoRecepcionOm.EtiquetaMedio("traslado_tw"));
        Assert.Equal("Parcial", CatalogoRecepcionOm.EtiquetaEstado("parcial"));
    }
}
