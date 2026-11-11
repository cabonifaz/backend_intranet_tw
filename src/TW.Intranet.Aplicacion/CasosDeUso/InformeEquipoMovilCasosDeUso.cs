using System.Text.Json;
using System.Text.Json.Serialization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-15 — Cabecera del informe · HU-16 — Hard Stop de cierre ───────────────────────

/// <summary>Límites y validación de forma de lo que llega al guardar la cabecera (el SP vuelve a validar todo y calcula E, EMP y conformidad).</summary>
public static class EntradaInformeEquipoMovil
{
    public const int MaxRecomendaciones = 20;
    public const int MaxFallas = 15;
    public const int MaxPruebasPorFalla = 12;
    public const int MaxFotosPorFalla = 5;
    public const int MaxCeldas = 12;
    public const decimal MaxValor = 100_000_000m;
    public const long TamanoMaximoFotoBytes = 6 * 1024 * 1024;

    public static readonly IReadOnlySet<string> Severidades = new HashSet<string> { "baja", "media", "alta", "critica" };
    public static readonly IReadOnlySet<string> Prioridades = new HashSet<string> { "alta", "media", "baja" };
    public static readonly IReadOnlySet<string> EstadosEquipo = new HashSet<string> { "operativo", "con_observaciones", "inoperativo" };
    public static readonly IReadOnlySet<string> TiposPrueba = new HashSet<string> { "repetibilidad", "pesaje", "excentricidad" };

    private static readonly JsonSerializerOptions Opciones = new(JsonSerializerDefaults.Web) { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    private static int Largo(string? t) => EntradaObjetivosMovil.Limpiar(t)?.Length ?? 0;

    /// <summary>Valida lo que llega; null si está bien, o el mensaje para el técnico.</summary>
    public static string? Validar(GuardarCabeceraInformeMovilDto? d)
    {
        if (d is null) return "Datos incompletos.";
        if (d.Datos is { } dt && (Largo(dt.ResponsableNombre) > 150 || Largo(dt.ResponsableCargo) > 100 || Largo(dt.ResponsableTelefono) > 30))
            return "Revisa \"Quién atiende en planta\": nombre hasta 150 caracteres, cargo hasta 100 y teléfono hasta 30.";

        if (d.Detalle is { } de)
        {
            if (Largo(de.TipoEquipo) > 60) return "El tipo de equipo no es válido.";
            if ((de.Celdas?.Count ?? 0) > MaxCeldas || (de.Celdas ?? []).Any(c => Math.Abs(c) > 100_000m)) return "Las celdas (mV) deben ser números, hasta 12 celdas.";
            if (de.SumatoriaHasta is < 0 or > MaxValor || de.ComparacionHasta is < 0 or > MaxValor) return "Las pruebas por sumatoria y por comparación deben ser valores positivos.";
            if ((de.Checks?.Count ?? 0) > 40 || (de.Checks ?? []).Any(c => Largo(c) is 0 or > 40)) return "El checklist no es válido.";
        }

        if (d.Recomendaciones is { } recs)
        {
            if (recs.Count > MaxRecomendaciones) return $"Se admiten hasta {MaxRecomendaciones} recomendaciones.";
            if (recs.Any(r => Largo(r.Titulo) is < 3 or > 200 || Largo(r.Descripcion) > 1000 || (r.Prioridad is not null && !Prioridades.Contains(r.Prioridad))))
                return "Cada recomendación necesita un texto de 3 a 200 caracteres y una prioridad válida.";
        }

        if (d.Fallas is { } fallas)
        {
            if (fallas.Count > MaxFallas) return $"Se admiten hasta {MaxFallas} fallas.";
            for (var i = 0; i < fallas.Count; i++)
            {
                var f = fallas[i];
                if (EntradaObjetivosMovil.Limpiar(f.Clasificacion) is null) return "Elige la clasificación de cada falla.";
                if (EntradaObjetivosMovil.Limpiar(f.Componente) is null) return "Elige el componente de cada falla.";
                if (f.Severidad is null || !Severidades.Contains(f.Severidad)) return "Elige la severidad de cada falla (Baja, Media, Alta o Crítica).";
                if (Largo(f.Descripcion) is < 5 or > 1000) return "Describe cada falla (de 5 a 1000 caracteres).";
                var pruebas = f.Pruebas ?? [];
                // REGLA de la HU-15: cada falla exige una prueba que la justifique
                if (pruebas.Count == 0) return $"La falla {i + 1} necesita una prueba que la justifique (Repetibilidad, Pesaje o Excentricidad con L e I).";
                if (pruebas.Count > MaxPruebasPorFalla) return $"Una falla admite hasta {MaxPruebasPorFalla} lecturas de prueba.";
                if (pruebas.Any(p => p.Tipo is null || !TiposPrueba.Contains(p.Tipo) || p.Carga is not (> 0 and <= MaxValor) || p.Indicacion is not (>= 0 and <= MaxValor) || p.Posicion is < 1 or > 9))
                    return "Revisa la prueba de cada falla: tipo válido, carga L mayor que 0 e indicación I digitada.";
                if ((f.Fotos?.Count ?? 0) > MaxFotosPorFalla || (f.Fotos ?? []).Any(x => x <= 0)) return $"Una falla admite hasta {MaxFotosPorFalla} fotos.";
            }
            if (fallas.SelectMany(f => f.Fotos ?? []).GroupBy(x => x).Any(g => g.Count() > 1)) return "Una foto no puede estar en dos fallas.";
        }

        if (d.Diagnostico is { } dg
            && ((dg.SeveridadGeneral is not null && !Severidades.Contains(dg.SeveridadGeneral)) || (dg.EstadoEquipo is not null && !EstadosEquipo.Contains(dg.EstadoEquipo))))
            return "El diagnóstico final no es válido: revisa la severidad general y el estado del equipo.";
        if (Largo(d.ComentarioPruebas) > 500) return "El comentario de las pruebas puede tener hasta 500 caracteres.";
        return null;
    }

    /// <summary>JSON que recibe el SP: solo las secciones que vienen (una sección ausente no se toca), con punto decimal.</summary>
    public static string ArmarJson(GuardarCabeceraInformeMovilDto d) => JsonSerializer.Serialize(d, Opciones);
}

/// <summary>Las 3 pestañas de la Cabecera del informe del equipo.</summary>
public class ObtenerCabeceraInformeMovilCasoDeUso(IInformeEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<CabeceraInformeMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<CabeceraInformeMovilDto>(1, "Servicio o equipo no encontrado."))
            : repositorio.ObtenerCabeceraAsync(idUsuario, idOs, idOsEquipo, ct);
}

/// <summary>Guarda las secciones de la cabecera y devuelve la cabecera ya actualizada (con E, EMP y conformidad calculados por el servidor).</summary>
public class GuardarCabeceraInformeMovilCasoDeUso(IInformeEquipoMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<CabeceraInformeMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, GuardarCabeceraInformeMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Servicio o equipo no encontrado.");
        if (EntradaInformeEquipoMovil.Validar(d) is { } error) return new(1, error);

        var r = await repositorio.GuardarCabeceraAsync(idUsuario, idOs, idOsEquipo, EntradaInformeEquipoMovil.ArmarJson(d!), ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);
        var cabecera = await repositorio.ObtenerCabeceraAsync(idUsuario, idOs, idOsEquipo, ct);
        return new(2, r.Mensaje, cabecera.IdTipoMensaje == 2 ? cabecera.Datos : null);
    }
}

/// <summary>
/// Sube la foto de una falla (JPEG de la cámara de la app, hasta 6 MB): se guarda en el almacén y el SP la registra suelta; su id se envía en "fotos" de la falla
/// al guardar la cabecera. No pasa por la IA ni cuenta en las 9 evidencias del registro fotográfico.
/// </summary>
public class SubirFotoFallaMovilCasoDeUso(IInformeEquipoMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<FotoFallaMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, long idOsEquipo, Stream? archivo, long tamano, decimal? latitud, decimal? longitud, decimal? precision, DateTime? capturadoUtc, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Servicio o equipo no encontrado.");
        if (latitud is < -90m or > 90m || longitud is < -180m or > 180m) return new(1, "La ubicación GPS no es válida.");
        if (precision is < 0m or > 5000m) return new(1, "La precisión del GPS no es válida.");
        if (archivo is null || tamano <= 0) return new(1, "Falta la foto.");
        if (tamano > EntradaInformeEquipoMovil.TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 6 MB.");

        using var m = new MemoryStream();
        await archivo.CopyToAsync(m, ct);
        if (m.Length == 0) return new(1, "La foto está vacía.");
        if (m.Length > EntradaInformeEquipoMovil.TamanoMaximoFotoBytes) return new(1, "La foto no puede superar los 6 MB.");
        var bytes = m.ToArray();
        if (bytes.Length < 3 || !RegistrarDemoraMovilCasoDeUso.EsJpeg(bytes.AsSpan(0, 3))) return new(1, "La foto debe ser una imagen JPEG tomada con la cámara.");

        var ruta = $"fallas/{idOs}/{idOsEquipo}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
        await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);
        var r = await repositorio.RegistrarFotoFallaAsync(idUsuario, idOs, idOsEquipo, ruta, latitud, longitud, precision, capturadoUtc, ct);
        if (r.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None); // sin registro no deben quedar archivos huérfanos
        return r;
    }
}

/// <summary>HU-16: el servidor valida las 5 etapas (una sola regla) y responde SIEMPRE: validación completa o los pendientes por etapa.</summary>
public class ValidarCierreEquipoMovilCasoDeUso(IInformeEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<CierreEquipoMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<CierreEquipoMovilDto>(1, "Servicio o equipo no encontrado."))
            : repositorio.ValidarCierreAsync(idUsuario, idOs, idOsEquipo, ct);
}

/// <summary>HU-16: con las 5 etapas conformes genera el informe técnico (N° NNNN-AAAA) y deja el equipo completado. Idempotente.</summary>
public class GenerarInformeEquipoMovilCasoDeUso(IInformeEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<InformeGeneradoMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<InformeGeneradoMovilDto>(1, "Servicio o equipo no encontrado."))
            : repositorio.GenerarInformeAsync(idUsuario, idOs, idOsEquipo, ct);
}
