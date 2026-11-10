using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-19 — Asistente IA y Procedimientos ───────────────────────────────────────────────────────────

/// <summary>Una fuente tal como se guarda con la consulta (respuesta_json): lo de la app más el texto que sigue al fragmento en el PDF.</summary>
public record FuenteAlmacenadaAsistente(
    int N, string IdDocumento, string Documento, string Tipo, string? Entidad, string? Version, string? Actualizado, string? Seccion, int? Pagina,
    string Fragmento, bool? Verificada, string? ContextoPosterior);

/// <summary>La respuesta del asistente tal como se guarda con la consulta (respuesta_json de asistente_consulta).</summary>
public record CuerpoRespuestaAsistente(
    bool Encontrada, string? Advertencia, List<string> Pasos, List<FuenteAlmacenadaAsistente> Fuentes, string? MotivoSinRespuesta);

/// <summary>Reglas de entrada del asistente: una sola vez aquí, las usan el controlador y los casos de uso.</summary>
public static class EntradaAsistenteMovil
{
    public const int MinPregunta = 3;
    public const int MaxPregunta = 500;
    public const int MaxBusqueda = 100;
    /// <summary>Documentos oficiales y bytes en total que se le dan a la IA en una consulta (el límite de una petición de Gemini con archivos en línea es de 20 MB).</summary>
    public const int  MaxDocumentos = 3;
    public const long MaxBytesDocumentos = 18L * 1024 * 1024;
    public const long MaxBytesAudio = 5L * 1024 * 1024;
    public const string IaNoDisponible = "El asistente IA no está disponible por ahora.";
    public const string SinDocumentos = "No hay manuales ni procedimientos oficiales cargados para este equipo.";
    public const string NoEncontrado = "No encontré este tema en los manuales oficiales de este equipo.";

    public static readonly IReadOnlySet<string> Origenes = new HashSet<string> { "texto", "voz", "sugerencia" };

    /// <summary>Quita caracteres de control, junta los espacios repetidos y recorta; vacío = null.</summary>
    public static string? LimpiarPregunta(string? texto)
    {
        // Los saltos de línea y tabulaciones son separadores: se pasan a espacio ANTES de quitar los caracteres de control (si no, "el\nerror" quedaría "elerror")
        var limpio = EntradaObjetivosMovil.Limpiar(texto is null ? null : Regex.Replace(texto, @"[\r\n\t\v\f\u0085  ]+", " "));
        return limpio is null ? null : Regex.Replace(limpio, @"\s+", " ");
    }

    /// <summary>Valida la consulta; devuelve el mensaje para el técnico o null si está bien (con la pregunta y el origen ya limpios).</summary>
    public static string? ValidarConsulta(PeticionConsultaAsistenteMovilDto? d, out string pregunta, out string origen)
    {
        pregunta = string.Empty;
        origen   = "texto";
        if (d is null) return "Datos incompletos.";
        if (d.IdOs is not > 0 || d.IdOsEquipo is not > 0) return EntradaObjetivosMovil.SinServicio;
        var p = LimpiarPregunta(d.Pregunta);
        if (p is null || p.Length < MinPregunta) return $"Escribe tu consulta (mínimo {MinPregunta} caracteres).";
        if (p.Length > MaxPregunta) return $"La consulta puede tener hasta {MaxPregunta} caracteres.";
        var o = (d.Origen ?? "texto").Trim().ToLowerInvariant();
        if (!Origenes.Contains(o)) return "El origen de la consulta no es válido.";
        pregunta = p;
        origen   = o;
        return null;
    }

    /// <summary>
    /// Tipo de audio por sus primeros bytes (no se confía en el tipo que declara la app): wav, mp3, aac (ADTS), mp4/m4a/3gp, ogg, flac o webm. null = no es audio reconocido.
    /// </summary>
    public static string? TipoAudio(ReadOnlySpan<byte> b)
    {
        if (b.Length < 12) return null;
        if (b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F' && b[8] == 'W' && b[9] == 'A' && b[10] == 'V' && b[11] == 'E') return "audio/wav";
        if (b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') return "audio/mp4";
        if (b[0] == 'I' && b[1] == 'D' && b[2] == '3') return "audio/mpeg";
        if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0)
            return ((b[1] >> 1) & 0x03) == 0 ? "audio/aac" : "audio/mpeg"; // capa 00 = ADTS (AAC); otra = MP3
        if (b[0] == 'O' && b[1] == 'g' && b[2] == 'g' && b[3] == 'S') return "audio/ogg";
        if (b[0] == 'f' && b[1] == 'L' && b[2] == 'a' && b[3] == 'C') return "audio/flac";
        if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) return "audio/webm";
        return null;
    }

    /// <summary>Texto transcrito listo para mostrar: sin caracteres de control, sin espacios repetidos y de hasta 500 caracteres.</summary>
    public static string? LimpiarTranscripcion(string? texto)
    {
        var t = LimpiarPregunta(texto);
        if (t is null) return null;
        return t.Length > MaxPregunta ? t[..MaxPregunta].TrimEnd() : t;
    }
}

/// <summary>Formato de la respuesta: lo guardado (JSON) y lo que ve la app.</summary>
public static class RespuestaAsistenteFormato
{
    public static readonly JsonSerializerOptions Opciones = new(JsonSerializerDefaults.Web) { WriteIndented = false };

    public static string Serializar(CuerpoRespuestaAsistente c) => JsonSerializer.Serialize(c, Opciones);

    public static CuerpoRespuestaAsistente? Leer(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<CuerpoRespuestaAsistente>(json, Opciones); }
        catch (JsonException) { return null; }
    }

    /// <summary>La respuesta de la app: las fuentes sin el texto de contexto del PDF (eso va solo en "Fuente consultada").</summary>
    public static RespuestaAsistenteMovilDto ARespuesta(CuerpoRespuestaAsistente c, long idConsulta, long idOs, long idOsEquipo, string pregunta, string origen, DateTime? creadoEn, bool? util) =>
        new(idConsulta, idOs, idOsEquipo, pregunta, origen, creadoEn, c.Encontrada, c.Encontrada ? c.Advertencia : null, c.Pasos ?? [],
            (c.Fuentes ?? []).Select(f => new FuenteRespuestaAsistenteMovilDto(f.N, f.IdDocumento, f.Documento, f.Tipo, f.Entidad, f.Version, f.Actualizado, f.Seccion, f.Pagina,
                f.Fragmento ?? string.Empty, f.Verificada)).ToList(),
            c.Encontrada ? null : c.MotivoSinRespuesta, util);

    public static RespuestaAsistenteMovilDto? ARespuesta(ConsultaGuardadaAsistente c)
    {
        var cuerpo = Leer(c.RespuestaJson);
        return cuerpo is null ? null : ARespuesta(cuerpo, c.IdConsulta, c.IdOs, c.IdOsEquipo, c.Pregunta, c.Origen, c.CreadoEn, c.Util);
    }

    public static FuenteConsultadaAsistenteMovilDto AFuente(CuerpoRespuestaAsistente c, FuenteAlmacenadaAsistente f, long idConsulta) =>
        new(idConsulta, f.N, f.IdDocumento, f.Documento, f.Tipo, true, f.Entidad, f.Version, f.Actualizado, f.Pagina, f.Seccion, c.Advertencia, f.Fragmento ?? string.Empty,
            f.ContextoPosterior, f.Verificada);
}

/// <summary>
/// Arma la respuesta del asistente a partir de lo que devolvió la IA. La regla de oro: sin fuente no hay respuesta. Si la IA dice que lo encontró pero no trae pasos
/// o no cita ningún documento válido, se trata como "no encontrado". Se recortan los textos, se numeran las fuentes y cada cita se comprueba contra el PDF.
/// </summary>
public static class ConstructorRespuestaAsistente
{
    public const int MaxPasos = 12;
    public const int MaxFuentes = 5;
    public const int MaxTextoPaso = 400;
    public const int MaxAdvertencia = 400;
    public const int MaxFragmento = 1200;
    public const int MaxSeccion = 200;
    public const int MaxMotivo = 300;
    public const string SinCitas = "La IA no pudo citar los manuales oficiales para esta consulta.";

    private static string? Recortar(string? s, int max)
    {
        var t = EntradaAsistenteMovil.LimpiarPregunta(s);
        return t is null ? null : t.Length > max ? t[..max].TrimEnd() : t;
    }

    private static FuenteAlmacenadaAsistente SinFragmento(int n, DocumentoAsistenteMovil d) =>
        new(n, d.IdDocumento, d.Titulo, d.Tipo, d.Entidad, d.Version, d.Actualizado, null, null, string.Empty, null, null);

    /// <summary>Respuesta de "no encontrado" o "sin documentos": sin advertencia ni pasos y con los documentos consultados como fuentes (sin fragmento).</summary>
    public static CuerpoRespuestaAsistente SinRespuesta(string motivo, IEnumerable<DocumentoAsistenteMovil> consultados) =>
        new(false, null, [], consultados.Select((d, i) => SinFragmento(i + 1, d)).ToList(), motivo);

    /// <summary>`verificar` comprueba una cita en el PDF del documento citado; null = no se verifica (queda sin verificar).</summary>
    public static (CuerpoRespuestaAsistente Cuerpo, string Estado) Construir(
        ResultadoAsistenteManuales ia, IReadOnlyList<DocumentoParaIa> usados, IReadOnlyDictionary<string, DocumentoAsistenteMovil> metadatos,
        Func<DocumentoParaIa, CitaAsistenteIa, VerificacionCitaAsistente>? verificar)
    {
        DocumentoAsistenteMovil Meta(DocumentoParaIa d) =>
            metadatos.TryGetValue(d.IdDocumento, out var m) ? m : new(d.IdDocumento, d.Tipo, d.Titulo, null, null, null, string.Empty, true);
        var consultados = usados.Select(Meta).ToList();

        if (!ia.Encontrada)
            return (SinRespuesta(Recortar(ia.Motivo, MaxMotivo) ?? EntradaAsistenteMovil.NoEncontrado, consultados), "sin_respuesta");

        var pasos = (ia.Pasos ?? []).Select(p => Recortar(p, MaxTextoPaso)).Where(p => p is not null).Select(p => p!).Take(MaxPasos).ToList();
        var fuentes = new List<FuenteAlmacenadaAsistente>();
        foreach (var c in ia.Citas ?? [])
        {
            if (fuentes.Count >= MaxFuentes) break;
            var fragmento = Recortar(c.Fragmento, MaxFragmento);
            if (fragmento is null || c.Documento < 1 || c.Documento > usados.Count) continue;
            var doc = usados[c.Documento - 1];
            var m = Meta(doc);
            var v = verificar?.Invoke(doc, c with { Fragmento = fragmento }) ?? new VerificacionCitaAsistente(null, null);
            fuentes.Add(new FuenteAlmacenadaAsistente(fuentes.Count + 1, m.IdDocumento, m.Titulo, m.Tipo, m.Entidad, m.Version, m.Actualizado,
                Recortar(c.Seccion, MaxSeccion), c.Pagina is > 0 and < 100000 ? c.Pagina : null, fragmento, v.Verificada, v.ContextoPosterior));
        }

        if (pasos.Count == 0 || fuentes.Count == 0) return (SinRespuesta(SinCitas, consultados), "sin_respuesta");

        return (new CuerpoRespuestaAsistente(true, Recortar(ia.Advertencia, MaxAdvertencia), pasos, fuentes, null), "respondida");
    }
}

/// <summary>Límite de transcripciones por técnico (en memoria; la consulta de texto tiene el suyo en el SP): 10 por minuto.</summary>
public static class LimitadorVozAsistente
{
    public const int MaxPorMinuto = 10;
    private static readonly ConcurrentDictionary<long, Queue<DateTime>> Usos = new();

    public static bool Permitir(long idUsuario, DateTime ahoraUtc)
    {
        var cola = Usos.GetOrAdd(idUsuario, _ => new Queue<DateTime>());
        lock (cola)
        {
            while (cola.Count > 0 && ahoraUtc - cola.Peek() >= TimeSpan.FromMinutes(1)) cola.Dequeue();
            if (cola.Count >= MaxPorMinuto) return false;
            cola.Enqueue(ahoraUtc);
            return true;
        }
    }
}

/// <summary>Inicio del asistente: equipo en contexto, documentos oficiales, sugerencias y consultas recientes. Sin ids, el equipo en ejecución del técnico.</summary>
public class ObtenerInicioAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public Task<RespuestaDto<InicioAsistenteMovilDto>> EjecutarAsync(long idUsuario, long? idOs, long? idOsEquipo, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<InicioAsistenteMovilDto>(1, "Usuario no válido."));
        if (idOs is <= 0 || idOsEquipo is <= 0 || (idOs is null) != (idOsEquipo is null))
            return Task.FromResult(new RespuestaDto<InicioAsistenteMovilDto>(1, EntradaObjetivosMovil.SinServicio));
        return repositorio.ObtenerInicioAsync(idUsuario, idOs, idOsEquipo, ct);
    }
}

/// <summary>Los equipos del técnico para "Cambiar" el contexto del asistente.</summary>
public class ObtenerEquiposAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public Task<RespuestaDto<List<EquipoAsistenteMovilDto>>> EjecutarAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<List<EquipoAsistenteMovilDto>>(1, "Usuario no válido."))
            : repositorio.ObtenerEquiposAsync(idUsuario, ct);
}

/// <summary>
/// Consulta al asistente. El orden importa: valida la entrada → IA configurada → documentos oficiales del equipo (y que el equipo sea del técnico) → registra la consulta
/// aplicando el límite de uso (así el límite cuenta aunque la IA falle) → lee los PDF → IA → comprueba las citas contra el PDF → completa la consulta.
/// Sin documentos oficiales no se llama a la IA. Nunca se responde sin fuente.
/// </summary>
public class ConsultarAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio, IAsistenteManuales ia, IDocumentosAsistente documentos)
{
    private static string DocumentosJson(IEnumerable<DocumentoAsistenteMovil> todos, ISet<string> usados) =>
        JsonSerializer.Serialize(todos.Select(d => new
        {
            idDocumento = d.IdDocumento, tipo = d.Tipo, titulo = d.Titulo,
            estado = usados.Contains(d.IdDocumento) ? "usado" : d.Disponible ? "omitido" : "no_disponible",
        }), RespuestaAsistenteFormato.Opciones);

    public async Task<RespuestaDto<RespuestaAsistenteMovilDto>> EjecutarAsync(long idUsuario, PeticionConsultaAsistenteMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return new(1, "Usuario no válido.");
        if (EntradaAsistenteMovil.ValidarConsulta(d, out var pregunta, out var origen) is { } error) return new(1, error);
        if (!ia.Disponible) return new(1, EntradaAsistenteMovil.IaNoDisponible);
        var idOs = d!.IdOs!.Value;
        var idOsEquipo = d.IdOsEquipo!.Value;

        var docs = await repositorio.ObtenerDocumentosAsync(idUsuario, idOs, idOsEquipo, ct);
        if (docs.IdTipoMensaje != 2 || docs.Datos is null) return new(docs.IdTipoMensaje, docs.Mensaje);

        var inicio = await repositorio.IniciarConsultaAsync(idUsuario, idOs, idOsEquipo, pregunta, origen, ct);
        if (inicio.IdTipoMensaje != 2 || inicio.Datos is null) return new(inicio.IdTipoMensaje, inicio.Mensaje);
        var idConsulta = inicio.Datos.IdConsulta;
        var reloj = Stopwatch.StartNew();

        async Task<RespuestaDto<RespuestaAsistenteMovilDto>> Cerrar(string estado, CuerpoRespuestaAsistente? cuerpo, IEnumerable<DocumentoAsistenteMovil> todos, ISet<string> usados)
        {
            var c = await repositorio.CompletarConsultaAsync(idUsuario, idConsulta, estado, DocumentosJson(todos, usados),
                cuerpo is null ? null : RespuestaAsistenteFormato.Serializar(cuerpo), ia.Motor, (int)Math.Min(reloj.ElapsedMilliseconds, int.MaxValue), CancellationToken.None);
            if (c.IdTipoMensaje != 2) return new(c.IdTipoMensaje, c.Mensaje);
            return new(2, "Éxito.", cuerpo is null ? null
                : RespuestaAsistenteFormato.ARespuesta(cuerpo, idConsulta, idOs, idOsEquipo, pregunta, origen, c.Datos?.CreadoEn ?? inicio.Datos.CreadoEn, null));
        }

        var todos = docs.Datos.Documentos;
        var seleccion = todos.Where(x => x.Disponible).Take(EntradaAsistenteMovil.MaxDocumentos).ToList();
        var ninguno = new HashSet<string>();

        try
        {
            if (seleccion.Count == 0)
                return await Cerrar("sin_fuentes", ConstructorRespuestaAsistente.SinRespuesta(EntradaAsistenteMovil.SinDocumentos, todos), todos, ninguno);

            var cargados = await documentos.CargarAsync(seleccion, ct);
            var paraIa = new List<DocumentoParaIa>();
            long bytes = 0;
            foreach (var c in cargados)
            {
                if (c.Pdf is null || bytes + c.Pdf.Length > EntradaAsistenteMovil.MaxBytesDocumentos) continue;
                bytes += c.Pdf.Length;
                paraIa.Add(new DocumentoParaIa(paraIa.Count + 1, c.Documento.IdDocumento, c.Documento.Titulo, c.Documento.Tipo, c.Pdf));
            }
            if (paraIa.Count == 0)
            {
                await Cerrar("error_ia", null, todos, ninguno);
                return new(1, "No se pudieron leer los documentos oficiales de este equipo. Inténtalo de nuevo en unos minutos.");
            }
            var usados = paraIa.Select(x => x.IdDocumento).ToHashSet();

            var resultado = await ia.ConsultarAsync(new SolicitudAsistenteManuales(pregunta, docs.Datos.Contexto, paraIa), ct);
            if (resultado.Error is not null)
            {
                await Cerrar("error_ia", null, todos, usados);
                return new(1, resultado.Error);
            }

            var metadatos = todos.ToDictionary(x => x.IdDocumento);
            var (cuerpo, estado) = ConstructorRespuestaAsistente.Construir(resultado, paraIa, metadatos, (doc, cita) => documentos.Verificar(doc.Pdf, cita.Pagina, cita.Fragmento));
            return await Cerrar(estado, cuerpo, todos, usados);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // el técnico cerró la app: la consulta queda registrada como error de la IA
            await repositorio.CompletarConsultaAsync(idUsuario, idConsulta, "error_ia", null, null, ia.Motor, (int)Math.Min(reloj.ElapsedMilliseconds, int.MaxValue), CancellationToken.None);
            throw;
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            await repositorio.CompletarConsultaAsync(idUsuario, idConsulta, "error_ia", null, null, ia.Motor, (int)Math.Min(reloj.ElapsedMilliseconds, int.MaxValue), CancellationToken.None);
            return new(1, "No se pudo consultar los manuales por ahora. Inténtalo de nuevo en unos minutos.");
        }
    }
}

/// <summary>Reabre una consulta reciente con su respuesta.</summary>
public class ObtenerConsultaAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<RespuestaAsistenteMovilDto>> EjecutarAsync(long idUsuario, long idConsulta, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idConsulta <= 0) return new(1, "Consulta no encontrada.");
        var r = await repositorio.ObtenerConsultaAsync(idUsuario, idConsulta, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        var respuesta = RespuestaAsistenteFormato.ARespuesta(r.Datos);
        return respuesta is null ? new(1, "La respuesta guardada no se pudo leer.") : new(2, r.Mensaje, respuesta);
    }
}

/// <summary>"¿Te sirvió la respuesta?": valoración de la consulta propia.</summary>
public class ValorarConsultaAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(long idUsuario, long idConsulta, PeticionValoracionAsistenteMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idConsulta <= 0) return Task.FromResult(new RespuestaDto<object>(1, "Consulta no encontrada."));
        if (d?.Util is null) return Task.FromResult(new RespuestaDto<object>(1, "La valoración no es válida."));
        return repositorio.ValorarConsultaAsync(idUsuario, idConsulta, d.Util.Value, ct);
    }
}

/// <summary>Pantalla "Fuente consultada": el documento, su sección y el fragmento que usó el asistente.</summary>
public class ObtenerFuenteAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<FuenteConsultadaAsistenteMovilDto>> EjecutarAsync(long idUsuario, long idConsulta, int n, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idConsulta <= 0) return new(1, "Consulta no encontrada.");
        var r = await repositorio.ObtenerConsultaAsync(idUsuario, idConsulta, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        var fuente = FuenteDe(r.Datos, n);
        return fuente is null ? new(1, "La fuente indicada no existe.") : new(2, r.Mensaje, fuente);
    }

    /// <summary>La fuente n de una consulta con respuesta (las de una respuesta "no encontrada" no tienen fragmento y no se abren); null si no existe.</summary>
    public static FuenteConsultadaAsistenteMovilDto? FuenteDe(ConsultaGuardadaAsistente consulta, int n)
    {
        var cuerpo = RespuestaAsistenteFormato.Leer(consulta.RespuestaJson);
        if (cuerpo is null || !cuerpo.Encontrada) return null;
        var f = cuerpo.Fuentes?.FirstOrDefault(x => x.N == n);
        return f is null ? null : RespuestaAsistenteFormato.AFuente(cuerpo, f, consulta.IdConsulta);
    }
}

/// <summary>Consulta por voz: transcribe el audio grabado en la app con Gemini (en español). El audio no se guarda.</summary>
public class TranscribirVozAsistenteMovilCasoDeUso(IAsistenteManuales ia)
{
    public async Task<RespuestaDto<TranscripcionVozAsistenteMovilDto>> EjecutarAsync(long idUsuario, byte[]? audio, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return new(1, "Usuario no válido.");
        if (audio is null || audio.Length == 0) return new(1, "Falta el audio de la consulta.");
        if (audio.Length > EntradaAsistenteMovil.MaxBytesAudio) return new(1, $"El audio no puede superar los {EntradaAsistenteMovil.MaxBytesAudio / 1024 / 1024} MB.");
        var tipo = EntradaAsistenteMovil.TipoAudio(audio);
        if (tipo is null) return new(1, "El audio no es válido. Graba de nuevo tu consulta.");
        if (!ia.Disponible) return new(1, EntradaAsistenteMovil.IaNoDisponible);
        if (!LimitadorVozAsistente.Permitir(idUsuario, DateTime.UtcNow)) return new(1, "Hiciste muchas consultas seguidas. Espera un minuto e inténtalo de nuevo.");

        var (texto, error) = await ia.TranscribirAsync(audio, tipo, ct);
        if (error is not null) return new(1, error);
        var limpio = EntradaAsistenteMovil.LimpiarTranscripcion(texto);
        return limpio is null || limpio.Length < EntradaAsistenteMovil.MinPregunta
            ? new(1, "No se entendió el audio. Inténtalo de nuevo.")
            : new(2, "Éxito.", new TranscripcionVozAsistenteMovilDto(limpio));
    }
}

/// <summary>"Guardados": respuestas y fragmentos que el técnico guardó, con buscador.</summary>
public class ListarGuardadosAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public Task<RespuestaDto<List<GuardadoAsistenteMovilDto>>> EjecutarAsync(long idUsuario, string? busqueda, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<List<GuardadoAsistenteMovilDto>>(1, "Usuario no válido."));
        var b = EntradaObjetivosMovil.Limpiar(busqueda);
        if (b is { Length: > EntradaAsistenteMovil.MaxBusqueda }) b = b[..EntradaAsistenteMovil.MaxBusqueda];
        return repositorio.ListarGuardadosAsync(idUsuario, b, ct);
    }
}

/// <summary>
/// "Guardar offline" y "Fragmento": guarda una copia de la respuesta o del fragmento citado. El contenido lo arma el back desde la consulta guardada (la app no puede
/// guardar texto inventado). La "descarga de sección" es el fragmento citado con su fuente, no un PDF recortado.
/// </summary>
public class GuardarAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    private static string? Recortar(string? s, int max) => s is null ? null : s.Length > max ? s[..max].TrimEnd() : s;

    /// <summary>Número de la sección ("6.4") si empieza con uno.</summary>
    public static string? NumeroSeccion(string? seccion)
    {
        if (string.IsNullOrWhiteSpace(seccion)) return null;
        var m = Regex.Match(seccion.Trim(), @"^\d+(\.\d+)*");
        return m.Success ? m.Value : null;
    }

    /// <summary>Título, subtítulo y contenido (JSON) del guardado; null si no corresponde (fuente inexistente).</summary>
    public static (string Titulo, string Subtitulo, string ContenidoJson)? Armar(ConsultaGuardadaAsistente consulta, string tipo, int n)
    {
        var cuerpo = RespuestaAsistenteFormato.Leer(consulta.RespuestaJson);
        if (cuerpo is null) return null;
        if (tipo == "respuesta")
        {
            var respuesta = RespuestaAsistenteFormato.ARespuesta(cuerpo, consulta.IdConsulta, consulta.IdOs, consulta.IdOsEquipo, consulta.Pregunta, consulta.Origen, consulta.CreadoEn, consulta.Util);
            var primera = cuerpo.Encontrada ? cuerpo.Fuentes?.FirstOrDefault() : null;
            var sec = NumeroSeccion(primera?.Seccion);
            var subtitulo = primera is null ? "Sin fuente · respuesta" : $"{primera.Documento}{(sec is null ? string.Empty : $" · §{sec}")} · respuesta";
            return (Recortar(consulta.Pregunta, 200)!, Recortar(subtitulo, 300)!, JsonSerializer.Serialize(new { respuesta }, RespuestaAsistenteFormato.Opciones));
        }
        var fuente = ObtenerFuenteAsistenteMovilCasoDeUso.FuenteDe(consulta, n);
        if (fuente is null) return null;
        var num = NumeroSeccion(fuente.Seccion);
        var titulo = num is not null ? $"Sección {num} completa" : fuente.Seccion ?? $"Fragmento de {fuente.Documento}";
        return (Recortar(titulo, 200)!, Recortar($"{fuente.Documento} · fragmento", 300)!, JsonSerializer.Serialize(new { fuente }, RespuestaAsistenteFormato.Opciones));
    }

    public async Task<RespuestaDto<GuardadoAsistenteCompletoMovilDto>> EjecutarAsync(long idUsuario, PeticionGuardarAsistenteMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return new(1, "Usuario no válido.");
        if (d?.IdConsulta is not > 0) return new(1, "Consulta no encontrada.");
        var tipo = (d.Tipo ?? string.Empty).Trim().ToLowerInvariant();
        if (tipo is not ("respuesta" or "fragmento")) return new(1, "Lo que quieres guardar no es válido.");
        var n = tipo == "respuesta" ? 0 : d.N ?? 0;
        if (tipo == "fragmento" && n is < 1 or > 20) return new(1, "La fuente indicada no existe.");

        var consulta = await repositorio.ObtenerConsultaAsync(idUsuario, d.IdConsulta.Value, ct);
        if (consulta.IdTipoMensaje != 2 || consulta.Datos is null) return new(consulta.IdTipoMensaje, consulta.Mensaje);
        var armado = Armar(consulta.Datos, tipo, n);
        if (armado is null) return new(1, tipo == "fragmento" ? "La fuente indicada no existe." : "La respuesta guardada no se pudo leer.");

        var r = await repositorio.GuardarAsync(idUsuario, d.IdConsulta.Value, tipo, n, armado.Value.Titulo, armado.Value.Subtitulo, armado.Value.ContenidoJson, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        return Completo(r.Datos) is { } completo ? new(2, r.Mensaje, completo) : new(1, "El guardado no se pudo leer.");
    }

    /// <summary>Un guardado de la base con su contenido leído (respuesta o fuente); null si el contenido está dañado.</summary>
    public static GuardadoAsistenteCompletoMovilDto? Completo(GuardadoCrudoAsistente g)
    {
        if (string.IsNullOrWhiteSpace(g.ContenidoJson)) return null;
        try
        {
            using var doc = JsonDocument.Parse(g.ContenidoJson);
            RespuestaAsistenteMovilDto? respuesta = null;
            FuenteConsultadaAsistenteMovilDto? fuente = null;
            if (doc.RootElement.TryGetProperty("respuesta", out var r) && r.ValueKind == JsonValueKind.Object)
                respuesta = r.Deserialize<RespuestaAsistenteMovilDto>(RespuestaAsistenteFormato.Opciones);
            if (doc.RootElement.TryGetProperty("fuente", out var f) && f.ValueKind == JsonValueKind.Object)
                fuente = f.Deserialize<FuenteConsultadaAsistenteMovilDto>(RespuestaAsistenteFormato.Opciones);
            return respuesta is null && fuente is null ? null
                : new GuardadoAsistenteCompletoMovilDto(g.IdGuardado, g.Tipo, g.Titulo, g.Subtitulo, g.CreadoEn, g.TamanoBytes, respuesta, fuente);
        }
        catch (JsonException) { return null; }
    }
}

/// <summary>Abre un guardado con su contenido completo (se lee sin conexión).</summary>
public class ObtenerGuardadoAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<GuardadoAsistenteCompletoMovilDto>> EjecutarAsync(long idUsuario, long idGuardado, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idGuardado <= 0) return new(1, "Guardado no encontrado.");
        var r = await repositorio.ObtenerGuardadoAsync(idUsuario, idGuardado, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        return GuardarAsistenteMovilCasoDeUso.Completo(r.Datos) is { } completo ? new(2, r.Mensaje, completo) : new(1, "El guardado no se pudo leer.");
    }
}

/// <summary>Quita un guardado (eliminación lógica con auditoría).</summary>
public class EliminarGuardadoAsistenteMovilCasoDeUso(IAsistenteMovilRepositorio repositorio)
{
    public Task<RespuestaDto<object>> EjecutarAsync(long idUsuario, long idGuardado, CancellationToken ct = default) =>
        idUsuario <= 0 || idGuardado <= 0
            ? Task.FromResult(new RespuestaDto<object>(1, "Guardado no encontrado."))
            : repositorio.EliminarGuardadoAsync(idUsuario, idGuardado, ct);
}
