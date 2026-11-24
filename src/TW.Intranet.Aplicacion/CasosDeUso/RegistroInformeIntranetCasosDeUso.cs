using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HU-55 — Registrar el informe de un equipo desde la intranet.
// Regla de oro: cada llamada pasa primero por SP_AutorizarRegistroIntranet (permiso, sesión propia y bloqueo) y los pasos reutilizan los casos de uso MÓVILES con el
// id del TÉCNICO que devolvió esa autorización. El id de quien registra NUNCA llega a un caso de uso móvil: así la lógica (Hard Stop, EMP, numeración) sigue en un solo lugar.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/// <summary>Reglas puras del registro desde la intranet: prefijo de conflicto (409), modos de autorización y validación de la hora de inicio y fin.</summary>
public static class ReglasRegistroIntranet
{
    /// <summary>Prefijo con el que el SP marca un conflicto de bloqueo (otra persona tiene el equipo): la API lo quita y responde HTTP 409.</summary>
    public const string PrefijoConflicto = "[409] ";
    public const string Lectura = "lectura";
    public const string Escritura = "escritura";
    public const int MaxComentario = 300;
    public const int MaxMotivoPausa = 200;
    public const string SinServicio = "Servicio o equipo no encontrado.";
    public const string SinTecnico = "El servicio no tiene un técnico asignado.";

    /// <summary>Lima es UTC−5 todo el año (sin horario de verano).</summary>
    private static readonly TimeSpan DesfaseLima = TimeSpan.FromHours(-5);
    private static readonly TimeSpan DuracionMaxima = TimeSpan.FromDays(7);
    private static readonly TimeSpan TolerianciaFuturo = TimeSpan.FromMinutes(1);

    public static bool EsConflicto(string? mensaje) => mensaje is not null && mensaje.StartsWith(PrefijoConflicto, StringComparison.Ordinal);

    public static string QuitarPrefijo(string? mensaje) => EsConflicto(mensaje) ? mensaje![PrefijoConflicto.Length..] : mensaje ?? string.Empty;

    /// <summary>
    /// Convierte el texto recibido a UTC. Sin zona (lo normal: "2026-11-24T08:30") es hora de Lima; con "Z" u offset se respeta. Null si no se puede leer.
    /// </summary>
    public static DateTime? LimaAUtc(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto) || texto.Length > 40) return null;
        if (!DateTime.TryParse(texto.Trim(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt)) return null;
        var utc = dt.Kind == DateTimeKind.Unspecified ? dt - DesfaseLima : dt.ToUniversalTime();
        return DateTime.SpecifyKind(utc, DateTimeKind.Unspecified);
    }

    /// <summary>Código de un motivo del catálogo (MAYÚSCULAS, dígitos y guion bajo, hasta 40).</summary>
    public static string? MotivoValido(string? motivo)
    {
        var m = EntradaObjetivosMovil.Limpiar(motivo)?.ToUpperInvariant();
        return m is { Length: >= 2 and <= 40 } && m.All(c => c is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or '_') ? m : null;
    }

    /// <summary>
    /// Valida el cuerpo de "iniciar-registro": inicio y fin legibles, inicio &lt; fin &lt;= ahora, duración menor a 7 días, motivo del catálogo y comentario de hasta 300.
    /// Devuelve las horas en UTC o el mensaje para quien registra.
    /// </summary>
    public static (DateTime InicioUtc, DateTime FinUtc, string Motivo, string? Comentario, string? Error) ValidarInicio(PeticionIniciarRegistroIntranetDto? d, DateTime ahoraUtc)
    {
        const string vacio = "";
        static (DateTime, DateTime, string, string?, string?) Falla(string e) => (default, default, vacio, null, e);
        if (d is null) return Falla("Datos incompletos.");
        if (string.IsNullOrWhiteSpace(d.Inicio)) return Falla("Indica la hora de inicio del trabajo en el equipo.");
        if (string.IsNullOrWhiteSpace(d.Fin)) return Falla("Indica la hora de fin del trabajo en el equipo.");
        if (LimaAUtc(d.Inicio) is not { } inicio) return Falla("La hora de inicio no es válida.");
        if (LimaAUtc(d.Fin) is not { } fin) return Falla("La hora de fin no es válida.");
        if (fin > ahoraUtc + TolerianciaFuturo) return Falla("La hora de fin no puede ser futura.");
        if (inicio >= fin) return Falla("La hora de inicio debe ser anterior a la de fin.");
        if (fin - inicio >= DuracionMaxima) return Falla("El trabajo en el equipo no puede durar 7 días o más.");
        var motivo = MotivoValido(d.Motivo);
        if (motivo is null) return Falla("Elige el motivo por el que se registra desde la intranet.");
        var comentario = EntradaObjetivosMovil.Limpiar(d.Comentario);
        if (comentario is { Length: > MaxComentario }) return Falla($"El comentario puede tener hasta {MaxComentario} caracteres.");
        return (inicio, fin, motivo, comentario, null);
    }
}

/// <summary>
/// Autoriza cada llamada y ejecuta la operación con el id del técnico. "Lectura" = permiso y resolver el técnico; "escritura" = además la sesión propia vigente (renovada) y, si la
/// operación terminó bien y se pide, estampa la trazabilidad (quién registró) en el informe del equipo.
/// </summary>
public class EjecutorRegistroIntranet(IRegistroInformeIntranetRepositorio repositorio)
{
    public Task<RespuestaDto<T>> LeerAsync<T>(long idRegistrador, long idOs, long idOsEquipo, Func<long, Task<RespuestaDto<T>>> operacion, CancellationToken ct) =>
        EjecutarAsync(ReglasRegistroIntranet.Lectura, idRegistrador, idOs, idOsEquipo, operacion, marcar: false, ct);

    public Task<RespuestaDto<T>> EscribirAsync<T>(long idRegistrador, long idOs, long idOsEquipo, Func<long, Task<RespuestaDto<T>>> operacion, bool marcar, CancellationToken ct) =>
        EjecutarAsync(ReglasRegistroIntranet.Escritura, idRegistrador, idOs, idOsEquipo, operacion, marcar, ct);

    /// <summary>A nivel de la OS (firma y constancia): solo permiso y resolver el técnico, porque la sesión del equipo ya se cerró al generar el informe.</summary>
    public Task<RespuestaDto<T>> PorOsAsync<T>(long idRegistrador, long idOs, Func<long, Task<RespuestaDto<T>>> operacion, CancellationToken ct) =>
        EjecutarAsync(ReglasRegistroIntranet.Lectura, idRegistrador, idOs, null, operacion, marcar: false, ct);

    /// <summary>Solo la autorización (para quien devuelve un archivo y no un RespuestaDto).</summary>
    public async Task<RespuestaDto<AutorizacionRegistroIntranetDto>> AutorizarAsync(string modo, long idRegistrador, long idOs, long? idOsEquipo, CancellationToken ct)
    {
        if (idRegistrador <= 0 || idOs <= 0 || idOsEquipo is <= 0) return new(1, ReglasRegistroIntranet.SinServicio);
        var a = await repositorio.AutorizarAsync(idRegistrador, idOs, idOsEquipo, modo, ct);
        if (a.IdTipoMensaje != 2) return a;
        return a.Datos is null || a.Datos.IdTecnico <= 0 ? new(1, ReglasRegistroIntranet.SinTecnico) : a;
    }

    private async Task<RespuestaDto<T>> EjecutarAsync<T>(
        string modo, long idRegistrador, long idOs, long? idOsEquipo, Func<long, Task<RespuestaDto<T>>> operacion, bool marcar, CancellationToken ct)
    {
        var a = await AutorizarAsync(modo, idRegistrador, idOs, idOsEquipo, ct);
        if (a.IdTipoMensaje != 2 || a.Datos is null) return new(a.IdTipoMensaje, a.Mensaje);

        var r = await operacion(a.Datos.IdTecnico);
        if (marcar && r.IdTipoMensaje == 2 && idOsEquipo is { } equipo)
        {
            var m = await repositorio.MarcarInformeAsync(idRegistrador, idOs, equipo, ct);
            if (m.IdTipoMensaje != 2) return new(m.IdTipoMensaje, m.Mensaje);
        }
        return r;
    }
}

/// <summary>"contexto-registro": todo para arrancar el asistente de registro. SOLO LECTURA: no marca llegada, no inicia el equipo y no toma el bloqueo.</summary>
public class ContextoRegistroIntranetCasoDeUso(IRegistroInformeIntranetRepositorio repositorio)
{
    public Task<RespuestaDto<ContextoRegistroIntranetDto>> EjecutarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idRegistrador <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<ContextoRegistroIntranetDto>(1, ReglasRegistroIntranet.SinServicio))
            : repositorio.ObtenerContextoAsync(idRegistrador, idOs, idOsEquipo, ct);
}

/// <summary>Sesión de registro: iniciar (llegada, inicio del equipo y bloqueo; idempotente), liberar y pausar el otro equipo que el técnico dejó abierto.</summary>
public class SesionRegistroIntranetCasoDeUso(IRegistroInformeIntranetRepositorio repositorio, TimeProvider? reloj = null)
{
    public Task<RespuestaDto<ResultadoIniciarRegistroIntranetDto>> IniciarAsync(
        long idRegistrador, long idOs, long idOsEquipo, PeticionIniciarRegistroIntranetDto? d, CancellationToken ct = default)
    {
        if (idRegistrador <= 0 || idOs <= 0 || idOsEquipo <= 0)
            return Task.FromResult(new RespuestaDto<ResultadoIniciarRegistroIntranetDto>(1, ReglasRegistroIntranet.SinServicio));
        var ahora = (reloj ?? TimeProvider.System).GetUtcNow().UtcDateTime;
        var v = ReglasRegistroIntranet.ValidarInicio(d, ahora);
        if (v.Error is not null) return Task.FromResult(new RespuestaDto<ResultadoIniciarRegistroIntranetDto>(1, v.Error));
        return repositorio.IniciarAsync(idRegistrador, idOs, idOsEquipo, v.InicioUtc, v.FinUtc, v.Motivo, v.Comentario, ct);
    }

    public Task<RespuestaDto<object>> LiberarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idRegistrador <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<object>(1, ReglasRegistroIntranet.SinServicio))
            : repositorio.LiberarAsync(idRegistrador, idOs, idOsEquipo, ct);

    public Task<RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>> PausarEquipoAbiertoAsync(
        long idRegistrador, long idOs, long idOsEquipo, PeticionPausarEquipoAbiertoIntranetDto? d, CancellationToken ct = default)
    {
        if (idRegistrador <= 0 || idOs <= 0 || idOsEquipo <= 0)
            return Task.FromResult(new RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>(1, ReglasRegistroIntranet.SinServicio));
        var motivo = EntradaObjetivosMovil.Limpiar(d?.Motivo);
        if (motivo is { Length: > ReglasRegistroIntranet.MaxMotivoPausa })
            return Task.FromResult(new RespuestaDto<ResultadoPausarEquipoAbiertoIntranetDto>(1, $"El motivo puede tener hasta {ReglasRegistroIntranet.MaxMotivoPausa} caracteres."));
        return repositorio.PausarEquipoAbiertoAsync(idRegistrador, idOs, idOsEquipo, motivo, ct);
    }
}

/// <summary>
/// "informe-en-curso": lo ya cargado del equipo (trabajo, evidencias, ensayos y cabecera) para retomar. Reutiliza los casos de uso móviles de lectura. Si una parte aún no se puede leer
/// (el equipo no está iniciado, por ejemplo) viene nula y en Avisos se explica por qué.
/// </summary>
public class InformeEnCursoIntranetCasoDeUso(
    EjecutorRegistroIntranet ejecutor,
    ObtenerTrabajoEquipoMovilCasoDeUso trabajo,
    ObtenerEvidenciasMovilCasoDeUso evidencias,
    ObtenerEnsayosMovilCasoDeUso ensayos,
    ObtenerCabeceraInformeMovilCasoDeUso cabecera)
{
    public Task<RespuestaDto<InformeEnCursoIntranetDto>> EjecutarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.LeerAsync(idRegistrador, idOs, idOsEquipo, async idTecnico =>
        {
            var avisos = new List<string>();
            var t = await trabajo.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct);
            var ev = await evidencias.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct);
            var en = await ensayos.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct);
            var ca = await cabecera.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct);
            static T? Dato<T>(RespuestaDto<T> r, string parte, List<string> avisos) where T : class
            {
                if (r.IdTipoMensaje == 2) return r.Datos;
                avisos.Add($"{parte}: {r.Mensaje}");
                return null;
            }
            return new RespuestaDto<InformeEnCursoIntranetDto>(2, "Éxito.", new InformeEnCursoIntranetDto(
                Dato(t, "Trabajo", avisos), Dato(ev, "Evidencias", avisos), Dato(en, "Ensayos", avisos), Dato(ca, "Cabecera", avisos), avisos));
        }, ct);
}

/// <summary>Variables ambientales. Fecha y hora las pone el servidor: aquí no hay hora de captura del teléfono.</summary>
public class TrabajoRegistroIntranetCasoDeUso(EjecutorRegistroIntranet ejecutor, GuardarVariablesAmbientalesMovilCasoDeUso variables)
{
    public Task<RespuestaDto<TrabajoEquipoMovilDto>> GuardarVariablesAsync(
        long idRegistrador, long idOs, long idOsEquipo, PeticionVariablesAmbientalesMovilDto? d, CancellationToken ct = default)
    {
        // Sin capturadoEn: es el servidor quien pone la hora
        var cuerpo = d is null ? null : new PeticionVariablesAmbientalesMovilDto { Temperatura = d.Temperatura, Humedad = d.Humedad, Procedencia = d.Procedencia };
        return ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, idTecnico => variables.EjecutarAsync(idTecnico, idOs, idOsEquipo, cuerpo, ct), marcar: false, ct);
    }
}

/// <summary>
/// Evidencias. La IA aplica igual que en el móvil. Forzar usa un SP propio de intranet que NO suma al scorecard del técnico. Sin GPS ni hora de captura del teléfono.
/// </summary>
public class EvidenciasRegistroIntranetCasoDeUso(
    EjecutorRegistroIntranet ejecutor,
    IRegistroInformeIntranetRepositorio repositorio,
    ObtenerEvidenciasMovilCasoDeUso obtener,
    RegistrarEvidenciaMovilCasoDeUso registrar,
    QuitarEvidenciaAdicionalMovilCasoDeUso quitarAdicional,
    ObtenerArchivoEvidenciaMovilCasoDeUso archivo)
{
    public Task<RespuestaDto<EvidenciasMovilDto>> ObtenerAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.LeerAsync(idRegistrador, idOs, idOsEquipo, idTecnico => obtener.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct), ct);

    public Task<RespuestaDto<ResultadoEvidenciaMovilDto>> RegistrarAsync(
        long idRegistrador, long idOs, long idOsEquipo, CapturaEvidenciaMovilDto? d, Stream? foto, long tamanoFoto, Stream? cuadro, long tamanoCuadro, CancellationToken ct = default)
    {
        var cuerpo = d is null ? null : d with { Latitud = null, Longitud = null, Precision = null, CapturadoUtc = null };
        return ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo,
            idTecnico => registrar.EjecutarAsync(idTecnico, idOs, idOsEquipo, cuerpo, foto, tamanoFoto, cuadro, tamanoCuadro, ct), marcar: false, ct);
    }

    public Task<RespuestaDto<EvidenciasMovilDto>> ForzarAsync(
        long idRegistrador, long idOs, long idOsEquipo, long idEvidencia, PeticionForzarEvidenciaMovilDto? d, CancellationToken ct = default)
    {
        if (idEvidencia <= 0) return Task.FromResult(new RespuestaDto<EvidenciasMovilDto>(1, "Evidencia no encontrada."));
        var motivo = EntradaObjetivosMovil.Limpiar(d?.Motivo);
        if (motivo is null || motivo.Length < ForzarEvidenciaMovilCasoDeUso.MinMotivo)
            return Task.FromResult(new RespuestaDto<EvidenciasMovilDto>(1, $"Escribe el motivo por el que aceptas la foto (mínimo {ForzarEvidenciaMovilCasoDeUso.MinMotivo} caracteres)."));
        if (motivo.Length > ForzarEvidenciaMovilCasoDeUso.MaxMotivo)
            return Task.FromResult(new RespuestaDto<EvidenciasMovilDto>(1, $"El motivo puede tener hasta {ForzarEvidenciaMovilCasoDeUso.MaxMotivo} caracteres."));

        return ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, async idTecnico =>
        {
            var r = await repositorio.ForzarEvidenciaAsync(idRegistrador, idOs, idOsEquipo, idEvidencia, motivo, ct);
            if (r.IdTipoMensaje != 2) return new RespuestaDto<EvidenciasMovilDto>(r.IdTipoMensaje, r.Mensaje);
            var panel = await obtener.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct);
            return new RespuestaDto<EvidenciasMovilDto>(2, r.Mensaje, panel.IdTipoMensaje == 2 ? panel.Datos : null);
        }, marcar: false, ct);
    }

    public Task<RespuestaDto<EvidenciasMovilDto>> QuitarAdicionalAsync(long idRegistrador, long idOs, long idOsEquipo, long idEvidencia, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, idTecnico => quitarAdicional.EjecutarAsync(idTecnico, idOs, idOsEquipo, idEvidencia, ct), marcar: false, ct);

    public async Task<(Stream? Contenido, string? TipoContenido, string? Mensaje)> ArchivoAsync(
        long idRegistrador, long idOs, long idOsEquipo, long idEvidencia, bool cuadro, CancellationToken ct = default)
    {
        var a = await ejecutor.AutorizarAsync(ReglasRegistroIntranet.Lectura, idRegistrador, idOs, idOsEquipo, ct);
        if (a.IdTipoMensaje != 2 || a.Datos is null) return (null, null, a.Mensaje);
        return await archivo.EjecutarAsync(a.Datos.IdTecnico, idOs, idOsEquipo, idEvidencia, cuadro, ct);
    }
}

/// <summary>Ensayos (pesaje y excentricidad): el servidor calcula error, EMP y conformidad; aquí solo se envían carga e indicación.</summary>
public class EnsayosRegistroIntranetCasoDeUso(EjecutorRegistroIntranet ejecutor, ObtenerEnsayosMovilCasoDeUso obtener, GuardarEnsayosMovilCasoDeUso guardar)
{
    public Task<RespuestaDto<EnsayosMovilDto>> ObtenerAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.LeerAsync(idRegistrador, idOs, idOsEquipo, idTecnico => obtener.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct), ct);

    public Task<RespuestaDto<EnsayosMovilDto>> GuardarAsync(long idRegistrador, long idOs, long idOsEquipo, GuardarEnsayosMovilDto? d, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, idTecnico => guardar.EjecutarAsync(idTecnico, idOs, idOsEquipo, d, ct), marcar: true, ct);
}

/// <summary>Cabecera del informe (Datos · Detalle Serv. · Observación y pruebas) y fotos de las fallas (sin GPS).</summary>
public class CabeceraRegistroIntranetCasoDeUso(
    EjecutorRegistroIntranet ejecutor,
    ObtenerCabeceraInformeMovilCasoDeUso obtener,
    GuardarCabeceraInformeMovilCasoDeUso guardar,
    SubirFotoFallaMovilCasoDeUso subirFoto)
{
    public Task<RespuestaDto<CabeceraInformeMovilDto>> ObtenerAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.LeerAsync(idRegistrador, idOs, idOsEquipo, idTecnico => obtener.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct), ct);

    public Task<RespuestaDto<CabeceraInformeMovilDto>> GuardarAsync(
        long idRegistrador, long idOs, long idOsEquipo, GuardarCabeceraInformeMovilDto? d, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, idTecnico => guardar.EjecutarAsync(idTecnico, idOs, idOsEquipo, d, ct), marcar: true, ct);

    public Task<RespuestaDto<FotoFallaMovilDto>> SubirFotoFallaAsync(
        long idRegistrador, long idOs, long idOsEquipo, Stream? archivo, long tamano, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo,
            idTecnico => subirFoto.EjecutarAsync(idTecnico, idOs, idOsEquipo, archivo, tamano, null, null, null, null, ct), marcar: true, ct);
}

/// <summary>
/// Correlativo y certificado (etapa 5 del Hard Stop, HU-14). El ticket se crea a nombre del TÉCNICO (el SP exige que quien guarda el certificado sea quien lo solicitó). La asignación la
/// hace Metrología aparte.
/// </summary>
public class CorrelativoRegistroIntranetCasoDeUso(EjecutorRegistroIntranet ejecutor, CorrelativosTecnicoMovilCasoDeUso correlativos)
{
    public Task<RespuestaDto<SolicitudCorrelativoDto>> ObtenerSolicitudAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.LeerAsync(idRegistrador, idOs, idOsEquipo, idTecnico => correlativos.ObtenerSolicitudAsync(idTecnico, idOs, idOsEquipo, ct), ct);

    public Task<RespuestaDto<TicketCreadoDto>> SolicitarAsync(long idRegistrador, long idOs, long idOsEquipo, SolicitarCorrelativoDto? d, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, idTecnico => correlativos.SolicitarAsync(idTecnico, idOs, idOsEquipo, d, ct), marcar: false, ct);

    public Task<RespuestaDto<CertificadoGuardadoDto>> GuardarCertificadoAsync(long idRegistrador, long idOs, long idOsEquipo, GuardarCertificadoDto? d, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, idTecnico => correlativos.GuardarCertificadoAsync(idTecnico, idOs, idOsEquipo, d, ct), marcar: true, ct);
}

/// <summary>Hard Stop (las 5 etapas) y generación del informe. Al generar: ajusta el tiempo del equipo, genera con el técnico, marca la trazabilidad y libera la sesión.</summary>
public class CierreRegistroIntranetCasoDeUso(
    EjecutorRegistroIntranet ejecutor,
    IRegistroInformeIntranetRepositorio repositorio,
    ValidarCierreEquipoMovilCasoDeUso validar,
    GenerarInformeEquipoMovilCasoDeUso generar)
{
    public Task<RespuestaDto<CierreEquipoMovilDto>> ValidarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.LeerAsync(idRegistrador, idOs, idOsEquipo, idTecnico => validar.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct), ct);

    public Task<RespuestaDto<InformeGeneradoMovilDto>> GenerarAsync(long idRegistrador, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        ejecutor.EscribirAsync(idRegistrador, idOs, idOsEquipo, async idTecnico =>
        {
            // Antes de generar: el tiempo del equipo queda en fin − inicio (la generación suma ahora − reanudado, que aquí es NULL)
            var ajuste = await repositorio.AjustarTiempoAsync(idRegistrador, idOs, idOsEquipo, ct);
            if (ajuste.IdTipoMensaje != 2) return new RespuestaDto<InformeGeneradoMovilDto>(ajuste.IdTipoMensaje, ajuste.Mensaje);

            var r = await generar.EjecutarAsync(idTecnico, idOs, idOsEquipo, ct);
            if (r.IdTipoMensaje != 2) return r;

            // Primero se marca quién registró (con la sesión todavía vigente) y recién después se libera
            var marca = await repositorio.MarcarInformeAsync(idRegistrador, idOs, idOsEquipo, ct);
            if (marca.IdTipoMensaje != 2) return new RespuestaDto<InformeGeneradoMovilDto>(marca.IdTipoMensaje, marca.Mensaje);

            // Liberar es "lo mejor posible": si falla, la sesión caduca sola a los 30 minutos sin actividad
            await repositorio.LiberarAsync(idRegistrador, idOs, idOsEquipo, ct);
            return r;
        }, marcar: false, ct);
}

/// <summary>
/// Firma de informes y constancia, a nivel de la OS. Solo "formato físico" (foto del papel firmado) y "cliente ausente": no hay firma por dispositivo en este flujo. No exige la sesión
/// del equipo porque se cierra al generar el informe; basta el permiso.
/// </summary>
public class FirmaConstanciaRegistroIntranetCasoDeUso(
    EjecutorRegistroIntranet ejecutor,
    ObtenerFirmasMovilCasoDeUso firmas,
    FirmarResponsableMovilCasoDeUso firmarResponsable,
    ObtenerConstanciaMovilCasoDeUso constancia,
    FirmarConstanciaMovilCasoDeUso firmarConstancia,
    ObtenerArchivoConstanciaMovilCasoDeUso archivoConstancia)
{
    public Task<RespuestaDto<FirmasMovilDto>> FirmasAsync(long idRegistrador, long idOs, CancellationToken ct = default) =>
        ejecutor.PorOsAsync(idRegistrador, idOs, idTecnico => firmas.EjecutarAsync(idTecnico, idOs, ct), ct);

    public Task<RespuestaDto<FirmasMovilDto>> FirmarFisicoAsync(long idRegistrador, long idOs, string? clave, Stream? foto, long tamano, string? nombre, CancellationToken ct = default) =>
        ejecutor.PorOsAsync(idRegistrador, idOs, idTecnico => firmarResponsable.EjecutarFisicoAsync(idTecnico, idOs, clave, foto, tamano, nombre, ct), ct);

    public Task<RespuestaDto<FirmasMovilDto>> FirmarAusenteAsync(long idRegistrador, long idOs, string? clave, PeticionFirmaAusenteIntranetDto? d, CancellationToken ct = default) =>
        ejecutor.PorOsAsync(idRegistrador, idOs,
            idTecnico => firmarResponsable.EjecutarAsync(idTecnico, idOs, clave, new PeticionFirmaResponsableMovilDto("ausente", null, d?.Motivo), ct), ct);

    public Task<RespuestaDto<ConstanciaMovilDto>> ConstanciaAsync(long idRegistrador, long idOs, CancellationToken ct = default) =>
        ejecutor.PorOsAsync(idRegistrador, idOs, idTecnico => constancia.EjecutarAsync(idTecnico, idOs, ct), ct);

    public Task<RespuestaDto<ConstanciaMovilDto>> ConstanciaFisicoAsync(long idRegistrador, long idOs, Stream? foto, long tamano, string? nombre, CancellationToken ct = default) =>
        ejecutor.PorOsAsync(idRegistrador, idOs, idTecnico => firmarConstancia.FisicoAsync(idTecnico, idOs, foto, tamano, nombre, ct), ct);

    public Task<RespuestaDto<ConstanciaMovilDto>> ConstanciaGenerarAsync(long idRegistrador, long idOs, CancellationToken ct = default) =>
        ejecutor.PorOsAsync(idRegistrador, idOs, idTecnico => firmarConstancia.GenerarAsync(idTecnico, idOs, ct), ct);

    public async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> ConstanciaArchivoAsync(long idRegistrador, long idOs, string? tipo, CancellationToken ct = default)
    {
        var a = await ejecutor.AutorizarAsync(ReglasRegistroIntranet.Lectura, idRegistrador, idOs, null, ct);
        if (a.IdTipoMensaje != 2 || a.Datos is null) return (null, null, a.Mensaje);
        return await archivoConstancia.EjecutarAsync(a.Datos.IdTecnico, idOs, tipo, ct);
    }
}
