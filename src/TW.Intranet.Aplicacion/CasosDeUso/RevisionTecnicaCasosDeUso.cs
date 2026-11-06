using System.Globalization;
using System.Text;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Revisión Técnica (Sprint 5, HU-56 a HU-59). El permiso, el alcance y las reglas de estado las vuelve a validar cada SP;
// aquí se normalizan los filtros y se validan formatos y tamaños antes de llegar a la base de datos.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

internal static class ValidacionRevisionTecnica
{
    public const int MaxElementos = 100;

    public static readonly string[] Grupos =
        ["todos", "pendientes", "revisados", "pendiente_revision", "pendiente_precotizacion", "revisado_sin_precot", "revisado_con_precot"];

    public static string? Recortar(string? v, int max)
    {
        if (string.IsNullOrWhiteSpace(v)) return null;
        v = v.Trim();
        return v.Length > max ? v[..max] : v;
    }

    /// <summary>Devuelve el primer error de longitud encontrado o null.</summary>
    public static string? Largo(string? valor, int max, string campo)
        => valor is not null && valor.Trim().Length > max ? $"{campo}: máximo {max} caracteres." : null;
}

/// <summary>HU-56 Bandeja de revisión de informes (tarjetas, filas y opciones de los filtros).</summary>
public class ObtenerBandejaInformesCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<BandejaInformesDto>> EjecutarAsync(FiltrosBandejaInformesDto f, long idUsuario, CancellationToken ct = default)
    {
        var error = Normalizar(f);
        return error is not null
            ? Task.FromResult(new RespuestaDto<BandejaInformesDto>(1, error))
            : repositorio.ObtenerBandejaAsync(f, false, idUsuario, ct);
    }

    internal static string? Normalizar(FiltrosBandejaInformesDto f)
    {
        f.Grupo = f.Grupo?.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(f.Grupo) && !ValidacionRevisionTecnica.Grupos.Contains(f.Grupo))
            return $"Estado no válido. Use: {string.Join(", ", ValidacionRevisionTecnica.Grupos)}.";
        if (f.FechaDesde is { } d && f.FechaHasta is { } h && d.Date > h.Date)
            return "La fecha desde no puede ser posterior a la fecha hasta.";
        f.Busqueda  = ValidacionRevisionTecnica.Recortar(f.Busqueda, 200);
        f.Pagina    = Math.Clamp(f.Pagina, 1, 10000);
        f.PorPagina = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina;
        return null;
    }
}

/// <summary>HU-56 "Exportar": la bandeja con los filtros aplicados, en CSV (abre en Excel).</summary>
public class ExportarBandejaInformesCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(FiltrosBandejaInformesDto f, long idUsuario, CancellationToken ct = default)
    {
        var error = ObtenerBandejaInformesCasoDeUso.Normalizar(f);
        if (error is not null) return new(1, error);
        var r = await repositorio.ObtenerBandejaAsync(f, true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var sb = new StringBuilder();
        sb.AppendLine("Fecha ejecución;N° OS;Cliente;RUC;Sede;Equipo;Código TW;N° serie;Técnico;Observaciones;Estado;Precotización;Horas en bandeja;SLA vencido;Revisado el;Revisor");
        foreach (var i in r.Datos.Items)
        {
            sb.AppendLine(string.Join(';',
                Celda(i.FechaEjecucion?.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture)), Celda(i.NumeroOs), Celda(i.RazonSocial),
                Celda(i.Ruc), Celda(i.Sede), Celda(i.Equipo), Celda(i.CodigoTw), Celda(i.NumeroSerie), Celda(i.Tecnico),
                Celda(i.ConObservaciones ? $"Con observaciones ({i.NObservaciones})" : "Sin observaciones"), Celda(i.EstadoLabel),
                Celda(i.NumeroPrecot), Celda(i.HorasEspera?.ToString(CultureInfo.InvariantCulture)), Celda(i.SlaVencido ? "Sí" : "No"),
                Celda(i.FechaRevision?.ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture)), Celda(i.Revisor)));
        }
        // BOM para que Excel lea bien las tildes
        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
        return new(2, "Exportación generada.",
            new ArchivoGeneradoDto(bytes, $"revision-informes-{DateTime.Now:yyyyMMdd-HHmm}.csv", "text/csv; charset=utf-8"));
    }

    /// <summary>Escapa ; y comillas y neutraliza fórmulas (=, +, -, @) contra la inyección CSV.</summary>
    private static string Celda(string? v)
    {
        if (string.IsNullOrEmpty(v)) return "";
        if (v[0] is '=' or '+' or '-' or '@' or '\t' or '\r') v = "'" + v;
        return v.Contains(';') || v.Contains('"') || v.Contains('\n') ? $"\"{v.Replace("\"", "\"\"")}\"" : v;
    }
}

/// <summary>HU-57 Detalle del informe (modal y pantalla de edición).</summary>
public class ObtenerDetalleInformeCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleInformeTecnicoDto>> EjecutarAsync(long idInforme, long idUsuario, CancellationToken ct = default)
        => idInforme <= 0
            ? Task.FromResult(new RespuestaDto<DetalleInformeTecnicoDto>(1, "Informe no válido."))
            : repositorio.ObtenerDetalleAsync(idInforme, idUsuario, ct);
}

/// <summary>HU-58 "Guardar cambios" de la edición del informe.</summary>
public class GuardarInformeTecnicoCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    private static readonly string[] TiposEnsayo   = ["pesaje", "excentricidad"];
    private static readonly string[] Resultados    = ["conforme", "no_conforme"];
    private static readonly string[] Niveles       = ["critico", "alto", "medio", "bajo"];
    private static readonly string[] Prioridades   = ["alta", "media", "baja"];
    private static readonly string[] Globales      = ["dentro", "fuera"];

    public Task<RespuestaDto<InformeGuardadoDto>> EjecutarAsync(long idInforme, GuardarInformeTecnicoDto? d, long idUsuario, CancellationToken ct = default)
    {
        if (idInforme <= 0 || d is null) return Error("Datos no válidos.");
        if (d.DescripcionComplementaria is null && d.Resultado is null && d.Procedimiento is null && d.Ensayos is null
            && d.Observaciones is null && d.Recomendaciones is null)
            return Error("No hay cambios que guardar.");

        var error = Validar(d);
        return error is not null ? Error(error) : repositorio.GuardarInformeAsync(idInforme, d, idUsuario, ct);
    }

    private static Task<RespuestaDto<InformeGuardadoDto>> Error(string mensaje)
        => Task.FromResult(new RespuestaDto<InformeGuardadoDto>(1, mensaje));

    internal static string? Validar(GuardarInformeTecnicoDto d)
    {
        if (d.DescripcionComplementaria is { Length: > 1000 }) return "La descripción complementaria admite hasta 1000 caracteres.";
        foreach (var lista in new[] { d.Procedimiento?.Count, d.Ensayos?.Count, d.Observaciones?.Count, d.Recomendaciones?.Count })
            if (lista > ValidacionRevisionTecnica.MaxElementos) return $"Cada sección admite hasta {ValidacionRevisionTecnica.MaxElementos} elementos.";

        if (d.Resultado is { } g)
        {
            g.ResultadoGlobal = g.ResultadoGlobal?.Trim().ToLowerInvariant();
            if (!string.IsNullOrEmpty(g.ResultadoGlobal) && !Globales.Contains(g.ResultadoGlobal)) return "Resultado global no válido: use dentro o fuera.";
            var e = ValidacionRevisionTecnica.Largo(g.Normativa, 120, "Normativa")
                 ?? ValidacionRevisionTecnica.Largo(g.PatronEnsayo, 200, "Patrón")
                 ?? ValidacionRevisionTecnica.Largo(g.ErrorMaximoDetalle, 150, "Detalle del error máximo")
                 ?? ValidacionRevisionTecnica.Largo(g.DecisionTecnica, 300, "Decisión técnica");
            if (e is not null) return e;
        }

        foreach (var p in d.Procedimiento ?? [])
        {
            if (string.IsNullOrWhiteSpace(p.Titulo)) return "Cada paso del procedimiento debe tener un título.";
            var e = ValidacionRevisionTecnica.Largo(p.Titulo, 200, "Título del paso") ?? ValidacionRevisionTecnica.Largo(p.Detalle, 500, "Detalle del paso")
                 ?? ValidacionRevisionTecnica.Largo(p.Nota, 300, "Nota del paso");
            if (e is not null) return e;
        }

        foreach (var en in d.Ensayos ?? [])
        {
            en.Tipo      = en.Tipo?.Trim().ToLowerInvariant();
            en.Resultado = string.IsNullOrWhiteSpace(en.Resultado) ? null : en.Resultado.Trim().ToLowerInvariant();
            if (en.Tipo is null || !TiposEnsayo.Contains(en.Tipo)) return "Tipo de ensayo no válido: use pesaje o excentricidad.";
            if (string.IsNullOrWhiteSpace(en.Punto)) return "Cada lectura del ensayo debe indicar el punto de carga o la posición.";
            if (en.Resultado is not null && !Resultados.Contains(en.Resultado)) return "Resultado del ensayo no válido: use conforme o no_conforme.";
            var e = ValidacionRevisionTecnica.Largo(en.Punto, 100, "Punto del ensayo") ?? ValidacionRevisionTecnica.Largo(en.NotaPunto, 60, "Nota del punto");
            if (e is not null) return e;
            if (Fuera(en.Carga) || Fuera(en.Lectura) || Fuera(en.Error) || Fuera(en.Tolerancia)) return "Valor de ensayo fuera de rango.";
        }

        foreach (var o in d.Observaciones ?? [])
        {
            o.NivelAfectacion = string.IsNullOrWhiteSpace(o.NivelAfectacion) ? null : o.NivelAfectacion.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(o.Titulo)) return "Cada observación debe tener un título.";
            if (o.NivelAfectacion is not null && !Niveles.Contains(o.NivelAfectacion)) return "Nivel de afectación no válido: use critico, alto, medio o bajo.";
            var e = ValidacionRevisionTecnica.Largo(o.Titulo, 200, "Título de la observación")
                 ?? ValidacionRevisionTecnica.Largo(o.Descripcion, 1000, "Descripción de la observación")
                 ?? ValidacionRevisionTecnica.Largo(o.Ubicacion, 200, "Ubicación")
                 ?? ValidacionRevisionTecnica.Largo(o.DetalleExtra, 200, "Detalle de la observación");
            if (e is not null) return e;
        }

        var nObs = d.Observaciones?.Count ?? 0;
        foreach (var r in d.Recomendaciones ?? [])
        {
            r.Prioridad = string.IsNullOrWhiteSpace(r.Prioridad) ? "media" : r.Prioridad.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(r.Titulo)) return "Cada recomendación debe tener un título.";
            if (!Prioridades.Contains(r.Prioridad)) return "Prioridad no válida: use alta, media o baja.";
            if (r.IndiceObservacion is { } i && (i < 0 || i >= nObs)) return "La observación vinculada a una recomendación no existe en la lista enviada.";
            var e = ValidacionRevisionTecnica.Largo(r.Titulo, 200, "Título de la recomendación")
                 ?? ValidacionRevisionTecnica.Largo(r.Descripcion, 1000, "Descripción de la recomendación")
                 ?? ValidacionRevisionTecnica.Largo(r.Plazo, 100, "Plazo");
            if (e is not null) return e;
        }
        return null;
    }

    private static bool Fuera(decimal? v) => v is { } x && Math.Abs(x) >= 10_000_000_000m;
}

/// <summary>HU-58 Paso 4: registrar o actualizar la precotización (se envía a Comercial al guardarla).</summary>
public class GuardarPrecotizacionInformeCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    private static readonly string[] Prioridades = ["alta", "media", "opcional"];

    public Task<RespuestaDto<PrecotizacionGuardadaDto>> EjecutarAsync(long idInforme, GuardarPrecotizacionInformeDto? d, long idUsuario, CancellationToken ct = default)
    {
        if (idInforme <= 0 || d is null) return Error("Datos no válidos.");
        if (d.Items is null || d.Items.Count == 0) return Error("Agrega al menos un concepto a la precotización.");
        if (d.Items.Count > 50) return Error("La precotización admite hasta 50 conceptos.");
        if (d.Nota is { Length: > 1000 }) return Error("La nota admite hasta 1000 caracteres.");
        foreach (var i in d.Items)
        {
            i.Prioridad = string.IsNullOrWhiteSpace(i.Prioridad) ? "media" : i.Prioridad.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(i.Concepto) && i.IdSuministro is null or <= 0) return Error("Cada concepto debe tener un nombre o elegirse del catálogo.");
            if (i.Cantidad <= 0 || i.Cantidad > 99_999_999m) return Error("La cantidad de cada concepto debe ser mayor que cero.");
            if (!Prioridades.Contains(i.Prioridad)) return Error("Prioridad no válida: use alta, media u opcional.");
            var e = ValidacionRevisionTecnica.Largo(i.Concepto, 200, "Concepto") ?? ValidacionRevisionTecnica.Largo(i.Codigo, 60, "Código")
                 ?? ValidacionRevisionTecnica.Largo(i.DescripcionTecnica, 500, "Descripción técnica") ?? ValidacionRevisionTecnica.Largo(i.Unidad, 20, "Unidad");
            if (e is not null) return Error(e);
        }
        return repositorio.GuardarPrecotizacionAsync(idInforme, d, idUsuario, ct);
    }

    private static Task<RespuestaDto<PrecotizacionGuardadaDto>> Error(string mensaje)
        => Task.FromResult(new RespuestaDto<PrecotizacionGuardadaDto>(1, mensaje));
}

/// <summary>HU-59 Modal "Registrar Revisión del Informe": checklist de cumplimiento.</summary>
public class PrepararRevisionInformeCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionRevisionInformeDto>> EjecutarAsync(long idInforme, long idUsuario, CancellationToken ct = default)
        => idInforme <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionRevisionInformeDto>(1, "Informe no válido."))
            : repositorio.PrepararRevisionAsync(idInforme, idUsuario, ct);
}

/// <summary>HU-59 "Confirmar Revisión": el informe queda revisado e inmutable.</summary>
public class RegistrarRevisionInformeCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<InformeRevisadoDto>> EjecutarAsync(long idInforme, RegistrarRevisionInformeDto? d, long idUsuario, CancellationToken ct = default)
    {
        if (idInforme <= 0) return Task.FromResult(new RespuestaDto<InformeRevisadoDto>(1, "Informe no válido."));
        if (d?.Nota is { Length: > 500 }) return Task.FromResult(new RespuestaDto<InformeRevisadoDto>(1, "La nota admite hasta 500 caracteres."));
        return repositorio.RegistrarRevisionAsync(idInforme, d?.Nota, idUsuario, ct);
    }
}

/// <summary>HU-59 Pestaña "Historial" (auditoría inmutable) con filtro por categoría.</summary>
public class ObtenerHistorialInformeCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    private static readonly string[] Categorias = ["todos", "edicion", "precotizacion", "revision", "sistema"];

    public Task<RespuestaDto<HistorialInformeDto>> EjecutarAsync(long idInforme, string? categoria, long idUsuario, CancellationToken ct = default)
    {
        categoria = categoria?.Trim().ToLowerInvariant();
        if (idInforme <= 0) return Task.FromResult(new RespuestaDto<HistorialInformeDto>(1, "Informe no válido."));
        if (!string.IsNullOrEmpty(categoria) && !Categorias.Contains(categoria))
            return Task.FromResult(new RespuestaDto<HistorialInformeDto>(1, $"Categoría no válida. Use: {string.Join(", ", Categorias)}."));
        return repositorio.ObtenerHistorialAsync(idInforme, categoria, idUsuario, ct);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HU-60 Precotizaciones Técnicas (CRM)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

public class ObtenerBandejaPrecotizacionesCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    private static readonly string[] Estados = ["todas", "pendiente", "convertida"];

    public Task<RespuestaDto<BandejaPrecotizacionesDto>> EjecutarAsync(FiltrosPrecotizacionesDto f, long idUsuario, CancellationToken ct = default)
    {
        f.Estado = f.Estado?.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(f.Estado) && !Estados.Contains(f.Estado))
            return Task.FromResult(new RespuestaDto<BandejaPrecotizacionesDto>(1, "Estado no válido: use pendiente, convertida o todas."));
        if (f.FechaDesde is { } d && f.FechaHasta is { } h && d.Date > h.Date)
            return Task.FromResult(new RespuestaDto<BandejaPrecotizacionesDto>(1, "La fecha desde no puede ser posterior a la fecha hasta."));
        f.Busqueda  = ValidacionRevisionTecnica.Recortar(f.Busqueda, 200);
        f.Pagina    = Math.Clamp(f.Pagina, 1, 10000);
        f.PorPagina = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina;
        return repositorio.ObtenerBandejaPrecotizacionesAsync(f, idUsuario, ct);
    }
}

public class ObtenerDetallePrecotizacionCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<DetallePrecotizacionDto>> EjecutarAsync(long idPrecotizacion, long idUsuario, CancellationToken ct = default)
        => idPrecotizacion <= 0
            ? Task.FromResult(new RespuestaDto<DetallePrecotizacionDto>(1, "Precotización no válida."))
            : repositorio.ObtenerDetallePrecotizacionAsync(idPrecotizacion, idUsuario, ct);
}

/// <summary>"Generar Propuesta Comercial": datos para precargar el wizard de la nueva propuesta.</summary>
public class ObtenerPrecargaPrecotizacionCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<PrecargaPrecotizacionDto>> EjecutarAsync(long idPrecotizacion, long idUsuario, CancellationToken ct = default)
        => idPrecotizacion <= 0
            ? Task.FromResult(new RespuestaDto<PrecargaPrecotizacionDto>(1, "Precotización no válida."))
            : repositorio.ObtenerPrecargaPrecotizacionAsync(idPrecotizacion, idUsuario, ct);
}

/// <summary>Vincula la precotización con la propuesta creada a partir de ella (la marca como convertida).</summary>
public class ConvertirPrecotizacionCasoDeUso(IRevisionTecnicaRepositorio repositorio)
{
    public Task<RespuestaDto<PrecotizacionConvertidaDto>> EjecutarAsync(long idPrecotizacion, ConvertirPrecotizacionDto? d, long idUsuario, CancellationToken ct = default)
    {
        if (idPrecotizacion <= 0 || d is null || d.IdPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<PrecotizacionConvertidaDto>(1, "Indique la propuesta generada."));
        return repositorio.ConvertirPrecotizacionAsync(idPrecotizacion, d.IdPropuesta, idUsuario, ct);
    }
}
