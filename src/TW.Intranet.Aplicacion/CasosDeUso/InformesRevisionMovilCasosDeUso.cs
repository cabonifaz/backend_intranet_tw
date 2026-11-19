using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-33 — Revisión de informes técnicos (Jefe de Área) ─────────────────────────────────────────────────────

/// <summary>
/// Validación de entrada de la revisión de informes. Desarrollo seguro: pestaña de lista cerrada, búsqueda con tope, códigos con formato fijo (el catálogo de motivos, secciones y plazos
/// vive SOLO en SP_ArmarCatalogoRevisionInformeMovil: el SP vuelve a validarlo), instrucción de 10 a 1000 caracteres sin caracteres de control y nota hasta 500.
/// </summary>
public static partial class ValidacionInformesRevisionMovil
{
    public static readonly string[] Grupos = ["por_revisar", "en_correccion", "aprobados"];
    public const int MaxBusqueda = 80;
    public const int MinInstruccion = 10;
    public const int MaxInstruccion = 1000;
    public const int MaxNota = 500;
    public const int MaxSecciones = 10;
    public const int MaxPlazoHoras = 720;

    [GeneratedRegex("^[a-z_]{1,30}$")]
    private static partial Regex CodigoValido();

    /// <summary>Pestaña normalizada (vacío = por_revisar); null si no es válida.</summary>
    public static string? NormalizarGrupo(string? grupo)
    {
        var g = (grupo ?? "").Trim().ToLowerInvariant();
        if (g.Length == 0) return Grupos[0];
        return Grupos.Contains(g) ? g : null;
    }

    /// <summary>(válida, texto): vacío = sin búsqueda; hasta 80 caracteres y sin caracteres de control.</summary>
    public static (bool Valida, string? Texto) NormalizarBusqueda(string? busqueda)
    {
        var t = (busqueda ?? "").Trim();
        if (t.Length == 0) return (true, null);
        if (t.Length > MaxBusqueda || t.Any(char.IsControl)) return (false, null);
        return (true, t);
    }

    private static bool TieneControl(string t) => t.Any(c => char.IsControl(c) && c is not ('\n' or '\r' or '\t'));

    /// <summary>Observar: devuelve el error o los valores ya normalizados (secciones en CSV, sin repetidas).</summary>
    public static (string? Error, string Motivo, string Secciones, string Instruccion, int PlazoHoras) NormalizarObservacion(ObservarInformeDto? d)
    {
        const string vacio = "";
        if (d is null) return ("Indica el motivo, las secciones, qué corregir y el plazo.", vacio, vacio, vacio, 0);

        var motivo = (d.Motivo ?? "").Trim().ToLowerInvariant();
        if (!CodigoValido().IsMatch(motivo)) return ("Elige el motivo de la observación.", vacio, vacio, vacio, 0);

        var secciones = (d.Secciones ?? []).Select(s => (s ?? "").Trim().ToLowerInvariant()).ToList();
        if (secciones.Count == 0) return ("Elige al menos una sección afectada.", vacio, vacio, vacio, 0);
        if (secciones.Count > MaxSecciones || secciones.Any(s => !CodigoValido().IsMatch(s))) return ("Alguna de las secciones indicadas no es válida.", vacio, vacio, vacio, 0);
        if (secciones.Distinct().Count() != secciones.Count) return ("Hay secciones repetidas.", vacio, vacio, vacio, 0);

        var instruccion = (d.Instruccion ?? "").Trim();
        if (instruccion.Length < MinInstruccion) return ($"Indica qué debe corregir el técnico (al menos {MinInstruccion} caracteres).", vacio, vacio, vacio, 0);
        if (instruccion.Length > MaxInstruccion) return ($"Lo que debe corregir admite hasta {MaxInstruccion} caracteres.", vacio, vacio, vacio, 0);
        if (TieneControl(instruccion)) return ("El texto tiene caracteres no permitidos.", vacio, vacio, vacio, 0);

        if (d.PlazoHoras is not > 0 or > MaxPlazoHoras) return ("Elige el plazo de la corrección.", vacio, vacio, vacio, 0);

        return (null, motivo, string.Join(',', secciones), instruccion, d.PlazoHoras!.Value);
    }

    /// <summary>Aprobar: la nota es opcional (hasta 500 caracteres, sin caracteres de control). Devuelve el error o la nota normalizada (null si no hay).</summary>
    public static (string? Error, string? Nota) NormalizarNota(AprobarInformeDto? d)
    {
        var nota = (d?.Nota ?? "").Trim();
        if (nota.Length == 0) return (null, null);
        if (nota.Length > MaxNota) return ($"La nota admite hasta {MaxNota} caracteres.", null);
        if (TieneControl(nota)) return ("La nota tiene caracteres no permitidos.", null);
        return (null, nota);
    }
}

/// <summary>Lista "Informes por revisar": KPIs sobre todo el alcance y las pestañas por revisar, en corrección y aprobados.</summary>
public class ObtenerInformesRevisionMovilCasoDeUso(IInformesRevisionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<InformesRevisionDto>> EjecutarAsync(long idUsuario, string? grupo, string? busqueda, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<InformesRevisionDto>(1, "No se pudo identificar al usuario."));
        var g = ValidacionInformesRevisionMovil.NormalizarGrupo(grupo);
        if (g is null) return Task.FromResult(new RespuestaDto<InformesRevisionDto>(1, "El grupo de informes no es válido."));
        var (valida, texto) = ValidacionInformesRevisionMovil.NormalizarBusqueda(busqueda);
        if (!valida) return Task.FromResult(new RespuestaDto<InformesRevisionDto>(1, $"La búsqueda no puede superar los {ValidacionInformesRevisionMovil.MaxBusqueda} caracteres."));
        return repositorio.ObtenerAsync(idUsuario, g, texto, ct);
    }
}

/// <summary>Detalle del informe: diagnóstico, validaciones, evidencias, corrección pedida y catálogos del modal "Observar informe".</summary>
public class ObtenerInformeRevisionMovilCasoDeUso(IInformesRevisionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<InformeRevisionDetalleDto>> EjecutarAsync(long idUsuario, long idInforme, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<InformeRevisionDetalleDto>(1, "No se pudo identificar al usuario."))
        : idInforme <= 0 ? Task.FromResult(new RespuestaDto<InformeRevisionDetalleDto>(1, "El informe indicado no es válido."))
        : repositorio.ObtenerDetalleAsync(idUsuario, idInforme, ct);
}

/// <summary>Archivo de una evidencia del informe (foto, video o con cuadro = true la miniatura del video), con el alcance del jefe.</summary>
public class ObtenerArchivoEvidenciaInformeMovilCasoDeUso(IInformesRevisionMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> EjecutarAsync(long idUsuario, long idInforme, long idEvidencia, bool cuadro, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idInforme <= 0 || idEvidencia <= 0) return (null, null, "Archivo no encontrado.");
        var r = await repositorio.ObtenerArchivoAsync(idUsuario, idInforme, idEvidencia, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return (null, null, r.Mensaje);
        var ruta = cuadro ? r.Datos.RutaCuadro : r.Datos.Ruta;
        if (string.IsNullOrWhiteSpace(ruta)) return (null, null, "Archivo no encontrado.");
        return await AbrirArchivoAprobacion.AbrirAsync(almacen, ruta, ct);
    }
}

/// <summary>Observar el informe: pide la corrección al técnico (motivo, secciones, qué corregir y plazo). Las reglas de negocio las valida el SP.</summary>
public class ObservarInformeMovilCasoDeUso(IInformesRevisionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ObservacionInformeResultadoDto>> EjecutarAsync(long idUsuario, long idInforme, ObservarInformeDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<ObservacionInformeResultadoDto>(1, "No se pudo identificar al usuario."));
        if (idInforme <= 0) return Task.FromResult(new RespuestaDto<ObservacionInformeResultadoDto>(1, "El informe indicado no es válido."));
        var v = ValidacionInformesRevisionMovil.NormalizarObservacion(dto);
        if (v.Error is not null) return Task.FromResult(new RespuestaDto<ObservacionInformeResultadoDto>(1, v.Error));
        return repositorio.ObservarAsync(idUsuario, idInforme, v.Motivo, v.Secciones, v.Instruccion, v.PlazoHoras, ct);
    }
}

/// <summary>Aprobar y liberar el informe: la misma revisión de la intranet (valida el checklist, lo cierra y avisa al técnico).</summary>
public class AprobarInformeMovilCasoDeUso(IInformesRevisionMovilRepositorio repositorio)
{
    public Task<RespuestaDto<AprobacionInformeResultadoDto>> EjecutarAsync(long idUsuario, long idInforme, AprobarInformeDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<AprobacionInformeResultadoDto>(1, "No se pudo identificar al usuario."));
        if (idInforme <= 0) return Task.FromResult(new RespuestaDto<AprobacionInformeResultadoDto>(1, "El informe indicado no es válido."));
        var (error, nota) = ValidacionInformesRevisionMovil.NormalizarNota(dto);
        if (error is not null) return Task.FromResult(new RespuestaDto<AprobacionInformeResultadoDto>(1, error));
        return repositorio.AprobarAsync(idUsuario, idInforme, nota, ct);
    }
}
