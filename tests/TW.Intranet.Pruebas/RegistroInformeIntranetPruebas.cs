using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.Extensions.Logging.Abstractions;
using TW.Intranet.API.Controllers;
using TW.Intranet.API.Seguridad;
using TW.Intranet.Aplicacion.CasosDeUso;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Pruebas;

/// <summary>Repositorio de la HU-55: registra cada llamada en una bitácora compartida con el repositorio móvil y responde lo configurado.</summary>
internal sealed class RegistroIntranetRepoFalso(List<string> bitacora) : IRegistroInformeIntranetRepositorio
{
    public RespuestaDto<AutorizacionRegistroIntranetDto> Autorizacion { get; set; } = new(2, "Éxito.", new(77, 5, true));
    public RespuestaDto<ResultadoIniciarRegistroIntranetDto> Inicio { get; set; } = new(2, "Éxito.", new(10, false, "en_ejecucion", "en_ejecucion", 77, 180));
    public RespuestaDto<ResultadoForzarEvidenciaMovilDto> Forzado { get; set; } = new(2, "Éxito.", new(3, null, 1, 0));
    public List<(string Modo, long? Equipo, long Registrador)> Autorizaciones { get; } = [];
    public List<long> RegistradoresForzar { get; } = [];
    public (long Registrador, DateTime InicioUtc, DateTime FinUtc, string Motivo, string? Comentario)? UltimoInicio { get; private set; }

    public Task<RespuestaDto<ContextoRegistroIntranetDto>> ObtenerContextoAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct)
    { bitacora.Add("Contexto"); return Task.FromResult(new RespuestaDto<ContextoRegistroIntranetDto>(2, "Éxito.")); }

    public Task<RespuestaDto<ResultadoIniciarRegistroIntranetDto>> IniciarAsync(
        long idRegistrador, long idOs, long idOsEquipo, DateTime inicioUtc, DateTime finUtc, string motivo, string? comentario, CancellationToken ct)
    { bitacora.Add("Iniciar"); UltimoInicio = (idRegistrador, inicioUtc, finUtc, motivo, comentario); return Task.FromResult(Inicio); }

    public Task<RespuestaDto<AutorizacionRegistroIntranetDto>> AutorizarAsync(long idRegistrador, long idOs, long? idOsEquipo, string modo, CancellationToken ct)
    { bitacora.Add($"Autorizar:{modo}"); Autorizaciones.Add((modo, idOsEquipo, idRegistrador)); return Task.FromResult(Autorizacion); }

    public Task<RespuestaDto<object>> LiberarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct)
    { bitacora.Add("Liberar"); return Task.FromResult(new RespuestaDto<object>(2, "Éxito.")); }

    public Task<RespuestaDto<object>> MarcarInformeAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct)
    { bitacora.Add("Marcar"); return Task.FromResult(new RespuestaDto<object>(2, "Éxito.")); }

    public Task<RespuestaDto<object>> AjustarTiempoAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct)
    { bitacora.Add("Ajustar"); return Task.FromResult(new RespuestaDto<object>(2, "Éxito.")); }

    public Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> ForzarEvidenciaAsync(long idRegistrador, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct)
    { bitacora.Add("ForzarIntranet"); RegistradoresForzar.Add(idRegistrador); return Task.FromResult(Forzado); }

    public Task<RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>> PausarEquipoAbiertoAsync(long idRegistrador, long idOs, long idOsEquipo, string? motivo, CancellationToken ct)
    { bitacora.Add("Pausar"); return Task.FromResult(new RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>(2, "Éxito.", new(idOs, 99, "Otro equipo"))); }
}

/// <summary>
/// Repositorio móvil con un solo objeto para las 4 lecturas y las escrituras que reutiliza la HU-55: guarda con qué usuario se lo llamó. Forzar es del SP móvil y aquí revienta a propósito:
/// desde la intranet se usa el SP propio (sin tocar el scorecard del técnico).
/// </summary>
internal sealed class RepoMovilFalso(List<string> bitacora) : ITrabajoEquipoMovilRepositorio, IEvidenciasMovilRepositorio, IEnsayosMovilRepositorio, IInformeEquipoMovilRepositorio
{
    public List<long> Usuarios { get; } = [];
    public RespuestaDto<TrabajoEquipoMovilDto> Trabajo { get; set; } = new(2, "Éxito.");
    public RespuestaDto<InformeGeneradoMovilDto> Generado { get; set; } = new(2, "Éxito.", new(1, "0001-2026", "completado", false));

    private Task<T> Llamar<T>(string operacion, long idUsuario, T respuesta)
    {
        bitacora.Add(operacion);
        Usuarios.Add(idUsuario);
        return Task.FromResult(respuesta);
    }

    // Trabajo en el equipo
    Task<RespuestaDto<TrabajoEquipoMovilDto>> ITrabajoEquipoMovilRepositorio.ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct, bool previo) =>
        Llamar("Trabajo", idUsuario, Trabajo);

    Task<RespuestaDto<ResultadoVariablesAmbientalesMovilDto>> ITrabajoEquipoMovilRepositorio.GuardarVariablesAsync(
        long idUsuario, long idOs, long idOsEquipo, decimal temperatura, decimal humedad, string? procedencia, DateTime? capturadoUtc, CancellationToken ct) =>
        Llamar("Variables", idUsuario, new RespuestaDto<ResultadoVariablesAmbientalesMovilDto>(2, "Éxito.", new(temperatura, humedad, "N.I", null, false, false)));

    // Evidencias
    Task<RespuestaDto<EvidenciasMovilDto>> IEvidenciasMovilRepositorio.ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct, bool previo) =>
        Llamar("Evidencias", idUsuario, new RespuestaDto<EvidenciasMovilDto>(2, "Éxito."));

    Task<RespuestaDto<ResultadoEvidenciaMovilDto>> IEvidenciasMovilRepositorio.RegistrarAsync(
        long idUsuario, long idOs, long idOsEquipo, string codigo, int pagina, string? rutaArchivo, string? rutaCuadro, decimal? duracionSeg,
        decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, string? qrTexto, ResultadoValidacionEvidenciaIa ia, CancellationToken ct) =>
        throw new NotSupportedException();

    Task<RespuestaDto<ResultadoForzarEvidenciaMovilDto>> IEvidenciasMovilRepositorio.ForzarAsync(
        long idUsuario, long idOs, long idOsEquipo, long idEvidencia, string motivo, CancellationToken ct) =>
        throw new InvalidOperationException("El SP móvil de forzar no debe usarse desde la intranet: suma al scorecard del técnico.");

    Task<RespuestaDto<object>> IEvidenciasMovilRepositorio.QuitarAdicionalAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct) =>
        throw new NotSupportedException();

    Task<RespuestaDto<ArchivoEvidenciaMovilDto>> IEvidenciasMovilRepositorio.ObtenerArchivoAsync(long idUsuario, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct) =>
        throw new NotSupportedException();

    // Ensayos
    Task<RespuestaDto<EnsayosMovilDto>> IEnsayosMovilRepositorio.ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        Llamar("Ensayos", idUsuario, new RespuestaDto<EnsayosMovilDto>(2, "Éxito."));

    Task<RespuestaDto<ResultadoGuardarEnsayosMovilDto>> IEnsayosMovilRepositorio.GuardarAsync(
        long idUsuario, long idOs, long idOsEquipo, string formaPlato, string json, string? motivo, bool finalizar, CancellationToken ct) =>
        throw new NotSupportedException();

    Task<RespuestaDto<ResultadoLlamadaEnsayoMovilDto>> IEnsayosMovilRepositorio.RegistrarLlamadaAsync(long idUsuario, long idOs, long idOsEquipo, string? detalle, CancellationToken ct) =>
        throw new NotSupportedException();

    // Informe del equipo
    Task<RespuestaDto<CabeceraInformeMovilDto>> IInformeEquipoMovilRepositorio.ObtenerCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct, bool previo) =>
        Llamar("Cabecera", idUsuario, new RespuestaDto<CabeceraInformeMovilDto>(2, "Éxito."));

    Task<RespuestaDto<ResultadoGuardarCabeceraMovilDto>> IInformeEquipoMovilRepositorio.GuardarCabeceraAsync(long idUsuario, long idOs, long idOsEquipo, string json, CancellationToken ct) =>
        throw new NotSupportedException();

    Task<RespuestaDto<FotoFallaMovilDto>> IInformeEquipoMovilRepositorio.RegistrarFotoFallaAsync(
        long idUsuario, long idOs, long idOsEquipo, string rutaArchivo, decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, CancellationToken ct) =>
        throw new NotSupportedException();

    Task<RespuestaDto<CierreEquipoMovilDto>> IInformeEquipoMovilRepositorio.ValidarCierreAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        throw new NotSupportedException();

    Task<RespuestaDto<InformeGeneradoMovilDto>> IInformeEquipoMovilRepositorio.GenerarInformeAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        Llamar("Generar", idUsuario, Generado);
}

/// <summary>Firmas: guarda con qué usuario, modo y motivo se firmó.</summary>
internal sealed class FirmaRepoFalso : IFirmaConstanciaMovilRepositorio
{
    public List<(long Usuario, string Clave, string Modo, string? Motivo)> Firmas { get; } = [];

    public Task<RespuestaDto<FirmasMovilDto>> ObtenerFirmasAsync(long idUsuario, long idOs, CancellationToken ct) => Task.FromResult(new RespuestaDto<FirmasMovilDto>(2, "Éxito."));
    public Task<RespuestaDto<ResumenFirmasMovilDto>> ObtenerResumenAsync(long idUsuario, long idOs, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<ComparablesFirmaMovilDto>> ObtenerComparablesAsync(long idUsuario, long idOs, string clave, CancellationToken ct) => throw new NotSupportedException();

    public Task<RespuestaDto<RegistroFirmaMovilDto>> GuardarFirmaAsync(
        long idUsuario, long idOs, string clave, string modo, string? trazos, string? hash, string? nombre, string? rutaFoto, string? motivo, CancellationToken ct)
    {
        Firmas.Add((idUsuario, clave, modo, motivo));
        return Task.FromResult(new RespuestaDto<RegistroFirmaMovilDto>(2, "Éxito.", new("ausente", 1, 1, 0, false, false, null)));
    }

    public Task<RespuestaDto<ConstanciaMovilDto>> ObtenerConstanciaAsync(long idUsuario, long idOs, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<RegistroConstanciaMovilDto>> GuardarConstanciaAsync(long idUsuario, long idOs, string accion, string? trazos, string? hash, string? nombre, string? rutaFoto, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<CierreConstanciaMovilDto>> RegistrarCierreAsync(long idUsuario, long idOs, string? rutaPdf, string envioEstado, string? envioDestino, string? envioDetalle, CancellationToken ct) => throw new NotSupportedException();
    public Task<RespuestaDto<string>> ObtenerRutaArchivoAsync(long idUsuario, long idOs, string tipo, CancellationToken ct) => throw new NotSupportedException();
}

internal sealed class RelojFijo(DateTime utc) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => new(DateTime.SpecifyKind(utc, DateTimeKind.Utc));
}

/// <summary>
/// HU-55 — Registrar el informe de un equipo desde la intranet: hora de Lima a UTC, validación de iniciar-registro, autorización por llamada, que a los casos de uso móviles
/// llegue SIEMPRE el id del técnico (nunca el de quien registra), el orden al generar el informe, forzar sin tocar el SP móvil, el 409 y el permiso de cada acción.
/// </summary>
public class RegistroInformeIntranetPruebas
{
    private static readonly DateTime Ahora = new(2026, 11, 24, 18, 0, 0, DateTimeKind.Utc);
    private const string Clave = "0123456789abcdef0123456789abcdef";

    private static PeticionIniciarRegistroIntranetDto Peticion(string? inicio = "2026-11-24T08:00", string? fin = "2026-11-24T11:00", string? motivo = "planta_sin_celular", string? comentario = null) =>
        new() { Inicio = inicio, Fin = fin, Motivo = motivo, Comentario = comentario };

    // ── Hora de Lima → UTC ─────────────────────────────────────────────────────────────────

    [Fact]
    public void Sin_zona_la_hora_es_de_Lima_y_se_suma_el_desfase()
        => Assert.Equal(new DateTime(2026, 11, 24, 13, 30, 0), ReglasRegistroIntranet.LimaAUtc("2026-11-24T08:30"));

    [Theory]
    [InlineData("2026-11-24T13:30:00Z")]
    [InlineData("2026-11-24T08:30:00-05:00")]
    public void Con_zona_se_respeta(string texto)
        => Assert.Equal(new DateTime(2026, 11, 24, 13, 30, 0), ReglasRegistroIntranet.LimaAUtc(texto));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("mañana a las ocho")]
    public void Una_hora_ilegible_no_se_convierte(string? texto)
        => Assert.Null(ReglasRegistroIntranet.LimaAUtc(texto));

    // ── Validación de iniciar-registro ─────────────────────────────────────────────────────

    [Fact]
    public void Un_inicio_correcto_devuelve_las_horas_en_UTC_y_el_motivo_en_mayusculas()
    {
        var v = ReglasRegistroIntranet.ValidarInicio(Peticion(comentario: "  Planta sin celulares  "), Ahora);
        Assert.Null(v.Error);
        Assert.Equal(new DateTime(2026, 11, 24, 13, 0, 0), v.InicioUtc);
        Assert.Equal(new DateTime(2026, 11, 24, 16, 0, 0), v.FinUtc);
        Assert.Equal("PLANTA_SIN_CELULAR", v.Motivo);
        Assert.Equal("Planta sin celulares", v.Comentario);
    }

    [Theory]
    [InlineData(null, "2026-11-24T11:00", "PLANTA_SIN_CELULAR", "Indica la hora de inicio del trabajo en el equipo.")]
    [InlineData("2026-11-24T08:00", " ", "PLANTA_SIN_CELULAR", "Indica la hora de fin del trabajo en el equipo.")]
    [InlineData("ayer", "2026-11-24T11:00", "PLANTA_SIN_CELULAR", "La hora de inicio no es válida.")]
    [InlineData("2026-11-24T08:00", "hoy", "PLANTA_SIN_CELULAR", "La hora de fin no es válida.")]
    [InlineData("2026-11-24T08:00", "2026-11-25T08:00", "PLANTA_SIN_CELULAR", "La hora de fin no puede ser futura.")]
    [InlineData("2026-11-24T11:00", "2026-11-24T11:00", "PLANTA_SIN_CELULAR", "La hora de inicio debe ser anterior a la de fin.")]
    [InlineData("2026-11-24T12:00", "2026-11-24T11:00", "PLANTA_SIN_CELULAR", "La hora de inicio debe ser anterior a la de fin.")]
    [InlineData("2026-11-10T08:00", "2026-11-17T08:00", "PLANTA_SIN_CELULAR", "El trabajo en el equipo no puede durar 7 días o más.")]
    [InlineData("2026-11-24T08:00", "2026-11-24T11:00", null, "Elige el motivo por el que se registra desde la intranet.")]
    [InlineData("2026-11-24T08:00", "2026-11-24T11:00", "planta sin celular", "Elige el motivo por el que se registra desde la intranet.")]
    [InlineData("2026-11-24T08:00", "2026-11-24T11:00", "X", "Elige el motivo por el que se registra desde la intranet.")]
    public void Un_inicio_incorrecto_se_rechaza_con_su_mensaje(string? inicio, string? fin, string? motivo, string esperado)
        => Assert.Equal(esperado, ReglasRegistroIntranet.ValidarInicio(Peticion(inicio, fin, motivo), Ahora).Error);

    [Fact]
    public void Un_comentario_de_mas_de_300_caracteres_se_rechaza()
        => Assert.Equal("El comentario puede tener hasta 300 caracteres.",
            ReglasRegistroIntranet.ValidarInicio(Peticion(comentario: new string('a', 301)), Ahora).Error);

    [Fact]
    public void Sin_cuerpo_los_datos_estan_incompletos()
        => Assert.Equal("Datos incompletos.", ReglasRegistroIntranet.ValidarInicio(null, Ahora).Error);

    [Fact]
    public void El_conflicto_se_reconoce_por_su_prefijo_y_se_limpia()
    {
        Assert.True(ReglasRegistroIntranet.EsConflicto("[409] Otra persona tiene este equipo."));
        Assert.False(ReglasRegistroIntranet.EsConflicto("Otra persona tiene este equipo."));
        Assert.Equal("Otra persona tiene este equipo.", ReglasRegistroIntranet.QuitarPrefijo("[409] Otra persona tiene este equipo."));
        Assert.Equal("Sin conflicto.", ReglasRegistroIntranet.QuitarPrefijo("Sin conflicto."));
    }

    // ── Sesión: iniciar ────────────────────────────────────────────────────────────────────

    [Fact]
    public async Task Iniciar_convierte_la_hora_de_Lima_y_la_pasa_al_repositorio_con_quien_registra()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var caso = new SesionRegistroIntranetCasoDeUso(intra, new RelojFijo(Ahora));

        var r = await caso.IniciarAsync(9, 1, 2, Peticion());

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal((9L, new DateTime(2026, 11, 24, 13, 0, 0), new DateTime(2026, 11, 24, 16, 0, 0), "PLANTA_SIN_CELULAR", (string?)null), intra.UltimoInicio);
    }

    [Fact]
    public async Task Iniciar_con_datos_invalidos_no_llega_al_repositorio()
    {
        var bit = new List<string>();
        var caso = new SesionRegistroIntranetCasoDeUso(new RegistroIntranetRepoFalso(bit), new RelojFijo(Ahora));

        var r = await caso.IniciarAsync(9, 1, 2, Peticion(motivo: null));

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Empty(bit);
    }

    [Fact]
    public async Task El_contexto_de_registro_solo_lee()
    {
        var bit = new List<string>();
        var r = await new ContextoRegistroIntranetCasoDeUso(new RegistroIntranetRepoFalso(bit)).EjecutarAsync(9, 1, 2);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(["Contexto"], bit);
    }

    // ── Los casos de uso móviles reciben al TÉCNICO, nunca a quien registra ────────────────────

    [Fact]
    public async Task Las_variables_se_guardan_con_el_id_del_tecnico_y_no_con_el_de_quien_registra()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var movil = new RepoMovilFalso(bit);
        var caso = new TrabajoRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), new GuardarVariablesAmbientalesMovilCasoDeUso(movil));

        var r = await caso.GuardarVariablesAsync(9, 1, 2, new PeticionVariablesAmbientalesMovilDto { Temperatura = 20m, Humedad = 55m });

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal([("escritura", (long?)2, 9L)], intra.Autorizaciones);
        Assert.NotEmpty(movil.Usuarios);
        Assert.All(movil.Usuarios, u => Assert.Equal(77, u));
    }

    [Fact]
    public async Task Sin_autorizacion_no_se_ejecuta_nada_del_movil()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit) { Autorizacion = new(1, "No tienes permiso para registrar el informe.") };
        var movil = new RepoMovilFalso(bit);
        var caso = new TrabajoRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), new GuardarVariablesAmbientalesMovilCasoDeUso(movil));

        var r = await caso.GuardarVariablesAsync(9, 1, 2, new PeticionVariablesAmbientalesMovilDto { Temperatura = 20m, Humedad = 55m });

        Assert.Equal((1, "No tienes permiso para registrar el informe."), (r.IdTipoMensaje, r.Mensaje));
        Assert.Empty(movil.Usuarios);
        Assert.Equal(["Autorizar:escritura"], bit);
    }

    [Fact]
    public async Task Un_servicio_sin_tecnico_asignado_no_se_registra()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit) { Autorizacion = new(2, "Éxito.", new(0, null, true)) };
        var movil = new RepoMovilFalso(bit);
        var caso = new TrabajoRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), new GuardarVariablesAmbientalesMovilCasoDeUso(movil));

        var r = await caso.GuardarVariablesAsync(9, 1, 2, new PeticionVariablesAmbientalesMovilDto { Temperatura = 20m, Humedad = 55m });

        Assert.Equal((1, ReglasRegistroIntranet.SinTecnico), (r.IdTipoMensaje, r.Mensaje));
        Assert.Empty(movil.Usuarios);
    }

    [Fact]
    public async Task El_informe_en_curso_junta_las_4_lecturas_con_el_tecnico_y_avisa_de_lo_que_no_se_puede_leer()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var movil = new RepoMovilFalso(bit) { Trabajo = new(1, "Primero inicia el trabajo en este equipo desde los objetivos.") };
        var caso = new InformeEnCursoIntranetCasoDeUso(new EjecutorRegistroIntranet(intra),
            new ObtenerTrabajoEquipoMovilCasoDeUso(movil), new ObtenerEvidenciasMovilCasoDeUso(movil), new ObtenerEnsayosMovilCasoDeUso(movil), new ObtenerCabeceraInformeMovilCasoDeUso(movil));

        var r = await caso.EjecutarAsync(9, 1, 2);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(["Trabajo: Primero inicia el trabajo en este equipo desde los objetivos."], r.Datos!.Avisos);
        Assert.Null(r.Datos.Trabajo);
        Assert.Equal([("lectura", (long?)2, 9L)], intra.Autorizaciones);
        Assert.Equal(["Autorizar:lectura", "Trabajo", "Evidencias", "Ensayos", "Cabecera"], bit);
        Assert.All(movil.Usuarios, u => Assert.Equal(77, u));
    }

    // ── Generar el informe ─────────────────────────────────────────────────────────────────

    [Fact]
    public async Task Al_generar_se_ajusta_el_tiempo_se_genera_con_el_tecnico_se_marca_y_se_libera_en_ese_orden()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var movil = new RepoMovilFalso(bit);
        var caso = new CierreRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), intra, new ValidarCierreEquipoMovilCasoDeUso(movil), new GenerarInformeEquipoMovilCasoDeUso(movil));

        var r = await caso.GenerarAsync(9, 1, 2);

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal(["Autorizar:escritura", "Ajustar", "Generar", "Marcar", "Liberar"], bit);
        Assert.Equal([77L], movil.Usuarios);
    }

    [Fact]
    public async Task Si_no_se_puede_generar_no_se_marca_ni_se_libera()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var movil = new RepoMovilFalso(bit) { Generado = new(1, "Faltan etapas por completar.") };
        var caso = new CierreRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), intra, new ValidarCierreEquipoMovilCasoDeUso(movil), new GenerarInformeEquipoMovilCasoDeUso(movil));

        var r = await caso.GenerarAsync(9, 1, 2);

        Assert.Equal((1, "Faltan etapas por completar."), (r.IdTipoMensaje, r.Mensaje));
        Assert.Equal(["Autorizar:escritura", "Ajustar", "Generar"], bit);
    }

    // ── Forzar sin tocar el SP móvil ───────────────────────────────────────────────────────

    [Fact]
    public async Task Forzar_usa_el_sp_de_intranet_con_quien_registra_y_nunca_el_del_movil()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var movil = new RepoMovilFalso(bit);
        var caso = new EvidenciasRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), intra, new ObtenerEvidenciasMovilCasoDeUso(movil), null!, null!, null!);

        var r = await caso.ForzarAsync(9, 1, 2, 30, new PeticionForzarEvidenciaMovilDto { Motivo = "La foto es legible aunque la IA la rechazó" });

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal([9L], intra.RegistradoresForzar);   // el SP propio sabe quién forzó
        Assert.Equal(["Autorizar:escritura", "ForzarIntranet", "Evidencias"], bit);
        Assert.Equal([77L], movil.Usuarios);              // el panel se lee con el técnico
    }

    [Theory]
    [InlineData(null)]
    [InlineData("ok")]
    public async Task Forzar_exige_un_motivo_de_al_menos_3_caracteres_y_no_toca_nada(string? motivo)
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var caso = new EvidenciasRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), intra, new ObtenerEvidenciasMovilCasoDeUso(new RepoMovilFalso(bit)), null!, null!, null!);

        var r = await caso.ForzarAsync(9, 1, 2, 30, new PeticionForzarEvidenciaMovilDto { Motivo = motivo });

        Assert.Equal(1, r.IdTipoMensaje);
        Assert.Empty(bit);
    }

    // ── Firma: solo físico y ausente, a nivel de la OS ─────────────────────────────────────

    [Fact]
    public async Task El_cliente_ausente_se_firma_con_el_tecnico_en_modo_ausente_y_a_nivel_de_la_OS()
    {
        var bit = new List<string>();
        var intra = new RegistroIntranetRepoFalso(bit);
        var firmaRepo = new FirmaRepoFalso();
        var caso = new FirmaConstanciaRegistroIntranetCasoDeUso(new EjecutorRegistroIntranet(intra), null!,
            new FirmarResponsableMovilCasoDeUso(firmaRepo, new AlmacenFalso(), null!), null!, null!, null!);

        var r = await caso.FirmarAusenteAsync(9, 1, Clave, new PeticionFirmaAusenteIntranetDto { Motivo = "El encargado no estuvo en planta" });

        Assert.Equal(2, r.IdTipoMensaje);
        Assert.Equal([(77L, Clave, "ausente", (string?)"El encargado no estuvo en planta")], firmaRepo.Firmas);
        Assert.Equal([("lectura", (long?)null, 9L)], intra.Autorizaciones);   // OS completa: sin equipo y sin exigir la sesión
    }

    // ── La API: 409, 400, 500 y el id del token como quien registra ────────────────────────

    private static RegistroInformeIntranetController Controlador(RegistroIntranetRepoFalso intra, long idToken = 9)
    {
        var controlador = new RegistroInformeIntranetController(
            new ContextoRegistroIntranetCasoDeUso(intra), new SesionRegistroIntranetCasoDeUso(intra, new RelojFijo(Ahora)),
            null!, null!, null!, null!, null!, null!, null!, null!, NullLogger<RegistroInformeIntranetController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, idToken.ToString())], "prueba")) }
            }
        };
        return controlador;
    }

    [Fact]
    public async Task Un_equipo_tomado_por_otra_persona_responde_409_sin_el_prefijo()
    {
        var intra = new RegistroIntranetRepoFalso([]) { Inicio = new(1, "[409] La asistente Ana Pérez tiene este equipo abierto.") };

        var resultado = Assert.IsAssignableFrom<ObjectResult>(await Controlador(intra).IniciarRegistro(1, 2, Peticion(), CancellationToken.None));

        Assert.Equal(409, resultado.StatusCode);
        var cuerpo = Assert.IsType<RespuestaDto<ResultadoIniciarRegistroIntranetDto>>(resultado.Value);
        Assert.Equal("La asistente Ana Pérez tiene este equipo abierto.", cuerpo.Mensaje);
    }

    [Fact]
    public async Task Una_regla_de_negocio_responde_400_y_el_exito_200()
    {
        var regla = new RegistroIntranetRepoFalso([]) { Inicio = new(1, "El técnico ya trabaja en otro equipo: pausa ese equipo primero.") };
        Assert.Equal(400, Assert.IsAssignableFrom<ObjectResult>(await Controlador(regla).IniciarRegistro(1, 2, Peticion(), CancellationToken.None)).StatusCode);

        var exito = Assert.IsAssignableFrom<ObjectResult>(await Controlador(new RegistroIntranetRepoFalso([])).IniciarRegistro(1, 2, Peticion(), CancellationToken.None));
        Assert.Equal(200, exito.StatusCode);
    }

    [Fact]
    public async Task Un_error_del_sistema_responde_500_sin_exponer_el_detalle()
    {
        var intra = new RegistroIntranetRepoFalso([]) { Inicio = new(3, "Table 'tw.registro_informe_intranet' doesn't exist") };

        var resultado = Assert.IsAssignableFrom<ObjectResult>(await Controlador(intra).IniciarRegistro(1, 2, Peticion(), CancellationToken.None));

        Assert.Equal(500, resultado.StatusCode);
        Assert.DoesNotContain("doesn't exist", Assert.IsType<RespuestaDto<ResultadoIniciarRegistroIntranetDto>>(resultado.Value).Mensaje);
    }

    [Fact]
    public async Task Quien_registra_es_el_usuario_del_token()
    {
        var intra = new RegistroIntranetRepoFalso([]);

        await Controlador(intra, idToken: 42).IniciarRegistro(1, 2, Peticion(), CancellationToken.None);

        Assert.Equal(42, intra.UltimoInicio!.Value.Registrador);
    }

    // ── Permiso: todas las acciones exigen seg_registrar_informe y viven fuera de api/movil ──

    private static readonly MethodInfo[] Acciones = typeof(RegistroInformeIntranetController)
        .GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
        .Where(m => m.GetCustomAttributes().Any(a => a is HttpMethodAttribute))
        .ToArray();

    [Fact]
    public void Se_exponen_todas_las_acciones_del_flujo()
        => Assert.Equal(28, Acciones.Length);

    [Fact]
    public void Todas_las_acciones_exigen_solo_seg_registrar_informe()
    {
        foreach (var accion in Acciones)
            Assert.Equal(["seg_registrar_informe"], accion.GetCustomAttribute<RequierePermisoAttribute>()?.Acciones ?? []);
    }

    [Fact]
    public void La_ruta_base_es_de_intranet_y_no_de_la_app_movil()
    {
        var ruta = typeof(RegistroInformeIntranetController).GetCustomAttribute<RouteAttribute>()!.Template;
        Assert.StartsWith("api/intranet/servicios/", ruta);
        Assert.DoesNotContain("movil", ruta);
    }
}
