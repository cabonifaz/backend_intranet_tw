using System.IO.Compression;
using System.Text;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ══════════════════════ Expediente Digital (Sprint 4, HU-29 a HU-33) ══════════════════════
// Consultivo: nace con el RQ, las etapas avanzan solas y los documentos y bloqueos se gestionan en los módulos origen.

/// <summary>Utilidades compartidas del módulo: textos, archivos del almacenamiento y correos de seguimiento (.eml).</summary>
internal static class ArchivoExpediente
{
    public const string TipoXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    public const string TipoPdf  = "application/pdf";
    public const string TipoEml  = "message/rfc822";

    public static string TipoContenido(string extension) => extension switch
    {
        ".pdf"  => TipoPdf,
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xlsx" => TipoXlsx,
        ".png"  => "image/png",
        ".jpg" or ".jpeg" => "image/jpeg",
        ".eml"  => TipoEml,
        _       => "application/octet-stream",
    };

    /// <summary>
    /// Solo letras (con tildes), dígitos, espacio y . _ - ( ): sin separadores de ruta (/ \ :) ni "..", en cualquier
    /// sistema operativo. Evita rutas manipuladas en el ZIP de exportación (zip slip) y en los nombres de descarga.
    /// </summary>
    public static string NombreSeguro(string? texto)
    {
        var sb = new StringBuilder();
        foreach (var c in (texto ?? "").Trim())
            sb.Append(char.IsLetterOrDigit(c) || c is ' ' or '.' or '_' or '-' or '(' or ')' ? c : '_');
        var limpio = sb.ToString();
        while (limpio.Contains("..")) limpio = limpio.Replace("..", ".");
        return limpio.Trim(' ', '.');
    }

    public static string? Recortar(string? texto, int maximo)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var t = texto.Trim();
        return t.Length > maximo ? t[..maximo] : t;
    }

    public static string? Codigo(string? texto, int maximo) => Recortar(texto, maximo)?.ToLowerInvariant();

    /// <summary>Abre un archivo del almacenamiento sin lanzar si la ruta no es válida (devuelve null).</summary>
    public static async Task<Stream?> AbrirAsync(IAlmacenArchivos almacen, string ruta, CancellationToken ct)
    {
        try { return await almacen.AbrirLecturaAsync(ruta, ct); }
        catch (InvalidOperationException) { return null; }
        catch (ArgumentException) { return null; }
        catch (IOException) { return null; }
    }

    /// <summary>Arma el correo de seguimiento enviado como archivo .eml (RFC 822, HTML en UTF-8).</summary>
    public static byte[] Eml(CorreoSeguimientoArchivoDto c)
    {
        static string Codificar(string? texto) =>
            $"=?UTF-8?B?{Convert.ToBase64String(Encoding.UTF8.GetBytes(texto ?? ""))}?=";

        var sb = new StringBuilder();
        if (!string.IsNullOrWhiteSpace(c.Remitente)) sb.Append("From: ").Append(c.Remitente).Append("\r\n");
        var para = Destinatarios(c.Para);
        if (para.Length > 0) sb.Append("To: ").Append(para).Append("\r\n");
        var cc = Destinatarios(c.Cc);
        if (cc.Length > 0) sb.Append("Cc: ").Append(cc).Append("\r\n");
        sb.Append("Subject: ").Append(Codificar(c.Asunto)).Append("\r\n");
        if (c.Fecha is { } f) sb.Append("Date: ").Append(new DateTimeOffset(f, TimeSpan.FromHours(-5)).ToString("r")).Append("\r\n");
        sb.Append("MIME-Version: 1.0\r\n");
        sb.Append("Content-Type: text/html; charset=utf-8\r\n");
        sb.Append("Content-Transfer-Encoding: base64\r\n\r\n");
        var cuerpo = Convert.ToBase64String(Encoding.UTF8.GetBytes(c.CuerpoHtml ?? ""));
        for (var i = 0; i < cuerpo.Length; i += 76)
            sb.Append(cuerpo, i, Math.Min(76, cuerpo.Length - i)).Append("\r\n");
        return Encoding.UTF8.GetBytes(sb.ToString());
    }

    /// <summary>JSON de destinatarios ([{"correo":..,"nombre":..}] o ["a@b.pe"]) → "a@b.pe, c@d.pe".</summary>
    private static string Destinatarios(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return "";
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return "";
            var correos = new List<string>();
            foreach (var e in doc.RootElement.EnumerateArray())
            {
                var correo = e.ValueKind switch
                {
                    JsonValueKind.String => e.GetString(),
                    JsonValueKind.Object when e.TryGetProperty("correo", out var p) => p.GetString(),
                    _ => null,
                };
                // Sin saltos de línea ni comas dentro de un destinatario (evita inyectar cabeceras)
                if (!string.IsNullOrWhiteSpace(correo) && correo.IndexOfAny(['\r', '\n', ',']) < 0) correos.Add(correo.Trim());
            }
            return string.Join(", ", correos);
        }
        catch (JsonException) { return ""; }
    }
}

// ── HU-29 Bandeja ────────────────────────────────────────────────────────────

/// <summary>Bandeja: tarjetas (filtros rápidos), tabla de 8 columnas y opciones de los filtros.</summary>
public class ObtenerBandejaExpedientesCasoDeUso(IExpedienteRepositorio repositorio)
{
    private static readonly string[] Estados =
        ["", "abiertos", "todos", "activo", "listo_para_avanzar", "bloqueado", "con_excepcion", "sla_vencido", "cerrado"];
    private static readonly string[] Slas = ["", "en_plazo", "en_riesgo", "vencido"];

    public Task<RespuestaDto<BandejaExpedientesDto>> EjecutarAsync(FiltrosBandejaExpedientesDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = Normalizar(f);
        return error is not null
            ? Task.FromResult(new RespuestaDto<BandejaExpedientesDto>(1, error))
            : repositorio.ObtenerBandejaAsync(filtros, false, idUsuario, ct);
    }

    internal static (FiltrosBandejaExpedientesDto Filtros, string? Error) Normalizar(FiltrosBandejaExpedientesDto f)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return (f, "Estado no válido. Use abiertos, listo_para_avanzar, bloqueado, con_excepcion, sla_vencido, activo, cerrado o todos.");
        var sla = f.Sla?.Trim().ToLowerInvariant() ?? "";
        if (!Slas.Contains(sla)) return (f, "SLA no válido. Use en_plazo, en_riesgo o vencido.");
        if (f.Desde is { } d && f.Hasta is { } h && d.Date > h.Date) return (f, "La fecha desde no puede ser posterior a la fecha hasta.");

        return (f with
        {
            Estado        = estado,
            Etapa         = ArchivoExpediente.Codigo(f.Etapa, 30),
            IdCliente     = f.IdCliente is > 0 ? f.IdCliente : null,
            Area          = ArchivoExpediente.Codigo(f.Area, 40),
            TipoPropuesta = ArchivoExpediente.Recortar(f.TipoPropuesta, 200),
            Desde         = f.Desde?.Date,
            Hasta         = f.Hasta?.Date,
            Sla           = sla == "" ? null : sla,
            Busqueda      = ArchivoExpediente.Recortar(f.Busqueda, 100),
            Pagina        = Math.Max(1, f.Pagina),
            PorPagina     = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina,
        }, null);
    }
}

/// <summary>HU-29 — Exportar XLSX: todas las filas con los filtros aplicados (las 8 columnas y datos de SLA).</summary>
public class ExportarBandejaExpedientesCasoDeUso(IExpedienteRepositorio repositorio, IGeneradorExcel excel)
{
    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(FiltrosBandejaExpedientesDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = ObtenerBandejaExpedientesCasoDeUso.Normalizar(f);
        if (error is not null) return new(1, error);

        var r = await repositorio.ObtenerBandejaAsync(filtros, true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var hoja = new HojaExcel("Expedientes",
            ["Expediente", "RQ", "Propuesta", "Otras propuestas", "Cliente", "RUC", "OC (cantidad)", "OC", "OS/OM",
             "Tipo de propuesta", "Etapa actual", "Estado", "Responsable", "Área", "SLA", "Vence", "Bloqueos", "Excepciones",
             "Creado", "Días"],
            r.Datos.Filas.Select(x => (IReadOnlyList<object?>)
            [
                x.Numero, x.NumeroRq, x.NumeroPropuesta is null ? null : $"{x.NumeroPropuesta} v{x.VersionPropuesta}",
                x.PropuestasOtras, x.RazonSocial, x.Ruc, x.CantidadOc, x.NumerosOc, x.NumeroOsOm, x.TipoPropuesta,
                x.EtapaNombre ?? x.Etapa, Estado(x.Estado), x.Responsable, x.AreaNombre, Sla(x.Sla.Estado), x.Sla.FechaLimite,
                x.Bloqueos, x.Excepciones, x.FechaCreacion, x.DiasTranscurridos,
            ]).ToList());

        return new(2, "Bandeja exportada.",
            new ArchivoGeneradoDto(excel.Generar([hoja]), $"Expedientes-{DateTime.Now:yyyyMMdd-HHmm}.xlsx", ArchivoExpediente.TipoXlsx));
    }

    internal static string Estado(string estado) => estado switch
    {
        "activo" => "Activo", "bloqueado" => "Bloqueado", "con_excepcion" => "Con excepción", "cerrado" => "Cerrado", _ => estado,
    };

    internal static string? Sla(string? estado) => estado switch
    {
        "en_plazo" => "En plazo", "en_riesgo" => "En riesgo", "vencido" => "Vencido", _ => estado,
    };
}

// ── HU-30 Ficha ──────────────────────────────────────────────────────────────

/// <summary>Sección primaria, KPIs y tab Resumen (lo único que carga al abrir la ficha).</summary>
public class ObtenerDetalleExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<DetalleExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerDetalleAsync(idExpediente, idUsuario, ct);
}

public class ObtenerTabRqExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabRqExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabRqExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabRqAsync(idExpediente, idUsuario, ct);
}

public class ObtenerTabPropuestasExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabPropuestasExpedienteDto>> EjecutarAsync(long idExpediente, long? idPropuesta, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabPropuestasExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabPropuestasAsync(idExpediente, idPropuesta is > 0 ? idPropuesta : null, idUsuario, ct);
}

/// <summary>Tab Propuestas, botón "Comparar versiones": solo versiones de propuestas del expediente.</summary>
public class CompararVersionesExpedienteCasoDeUso(IExpedienteRepositorio repositorio, CompararVersionesPropuestaCasoDeUso comparar)
{
    public async Task<RespuestaDto<ComparacionVersionesDto>> EjecutarAsync(
        long idExpediente, long idBase, long idDestino, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        if (idBase <= 0 || idDestino <= 0) return new(1, "Indique la versión base y la versión destino.");

        var v = await repositorio.ValidarComparacionAsync(idExpediente, idBase, idDestino, idUsuario, ct);
        if (v.IdTipoMensaje != 2) return new(v.IdTipoMensaje, v.Mensaje);
        return await comparar.EjecutarAsync(idBase, idDestino, idUsuario, ct);
    }
}

public class ObtenerTabVistoBuenoExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabVistoBuenoExpedienteDto>> EjecutarAsync(long idExpediente, string? numero, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabVistoBuenoExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabVistoBuenoAsync(idExpediente, ArchivoExpediente.Recortar(numero, 20), idUsuario, ct);
}

public class ObtenerTabSeguimientoExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabSeguimientoExpedienteDto>> EjecutarAsync(long idExpediente, string? numero, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabSeguimientoExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabSeguimientoAsync(idExpediente, ArchivoExpediente.Recortar(numero, 20), idUsuario, ct);
}

public class ObtenerTabOrdenesCompraExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabOrdenesCompraExpedienteDto>> EjecutarAsync(long idExpediente, long? idOc, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabOrdenesCompraExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabOrdenesCompraAsync(idExpediente, idOc is > 0 ? idOc : null, idUsuario, ct);
}

public class ObtenerTabOrdenServicioExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabOrdenServicioExpedienteDto>> EjecutarAsync(long idExpediente, long? idOs, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabOrdenServicioExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabOrdenServicioAsync(idExpediente, idOs is > 0 ? idOs : null, idUsuario, ct);
}

public class ObtenerTabProgramacionExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabProgramacionExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabProgramacionExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabProgramacionAsync(idExpediente, idUsuario, ct);
}

public class ObtenerTabSsomaExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabSsomaExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabSsomaExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabSsomaAsync(idExpediente, idUsuario, ct);
}

public class ObtenerTabEjecucionExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabEjecucionExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabEjecucionExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabEjecucionAsync(idExpediente, idUsuario, ct);
}

public class ObtenerTabCierreExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<TabCierreExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<TabCierreExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerTabCierreAsync(idExpediente, idUsuario, ct);
}

/// <summary>Hojas de Excel del expediente, compartidas por las exportaciones.</summary>
internal static class HojasExpediente
{
    private static string EstadoEtapa(string estado) => estado switch
    {
        "completado" => "Completado", "en_curso" => "En curso", "bloqueado" => "Bloqueado",
        "pendiente"  => "Pendiente",  "cancelado" => "Cancelado", "no_aplica" => "No aplica",
        _ => estado,
    };

    private static string Nivel(string nivel) => nivel switch
    {
        "advertencia" => "Advertencia", "riesgo" => "Riesgo", "vencido" => "Vencido", _ => nivel,
    };

    public static HojaExcel Resumen(CabeceraExpedienteDto c) => new("Resumen", ["Dato", "Valor"],
    [
        ["Expediente", c.Numero], ["Cliente", c.RazonSocial], ["RUC", c.Ruc], ["Requerimiento", c.NumeroRq],
        ["Propuesta activa", c.NumeroPropuesta is null ? null : $"{c.NumeroPropuesta} v{c.VersionPropuesta}"],
        ["Tipo de propuesta", c.TipoPropuesta], ["Monto total", c.MontoTotal], ["Moneda", c.Moneda],
        ["Etapa actual", c.EtapaNombre], ["Estado", ExportarBandejaExpedientesCasoDeUso.Estado(c.Estado)],
        ["Responsable", c.Responsable], ["Días transcurridos", c.DiasTranscurridos],
        ["SLA de la etapa", ExportarBandejaExpedientesCasoDeUso.Sla(c.Sla.Estado)], ["Vence", c.Sla.FechaLimite],
        ["Documentos", c.DocumentosTotales], ["Bloqueos activos", c.BloqueosActivos], ["Progreso (%)", c.Progreso],
        ["Exportado", DateTime.Now],
    ]);

    public static HojaExcel Etapas(IReadOnlyList<EtapaExpedienteDto> etapas) => new("Etapas",
        ["Etapa", "Estado", "Área", "Responsable", "Inicio", "Fin", "SLA (h)", "Horas reales", "Cumple SLA"],
        etapas.Select(e => (IReadOnlyList<object?>)
        [
            e.Nombre, EstadoEtapa(e.Estado), e.AreaNombre, e.Responsable, e.Inicio, e.Fin, e.SlaHoras, e.HorasReales,
            e.CumpleSla is null ? null : e.CumpleSla.Value ? "Sí" : "No",
        ]).ToList());

    public static HojaExcel Entidades(IReadOnlyList<EntidadExpedienteDto> entidades) => new("Entidades",
        ["Nivel", "Entidad", "Código", "Versión", "Estado", "Monto", "Responsable", "Fecha", "Detalle", "Activa"],
        entidades.Select(e => (IReadOnlyList<object?>)
        [
            e.Nivel, e.EntidadTipo.Replace('_', ' '), e.Codigo, e.Version, e.Estado?.Replace('_', ' '), e.Monto, e.Responsable,
            e.Fecha, e.Detalle, e.Activa ? "Sí" : "No",
        ]).ToList());

    public static HojaExcel Timeline(IReadOnlyList<EventoExpedienteDto> eventos) => new("Timeline",
        ["Fecha", "Tipo", "Evento", "Detalle", "Etapa", "Usuario", "Entidad", "Origen"],
        eventos.Select(e => (IReadOnlyList<object?>)
            [e.Fecha, e.TipoEvento?.Replace('_', ' '), e.Titulo, e.Descripcion, e.EtapaNombre ?? e.Etapa, e.Usuario, e.Referencia, e.Origen]).ToList());

    public static HojaExcel Reasignaciones(IReadOnlyList<ReasignacionHistorialDto> lista) => new("Reasignaciones",
        ["Fecha", "Entidad / alcance", "De", "A", "Motivo", "Comentario", "Decisión SLA", "Ejecutado por"],
        lista.Select(x => (IReadOnlyList<object?>)
            [x.Fecha, x.Alcance, x.De, x.A, x.Motivo, x.Comentario, x.DecisionSla, x.EjecutadoPor]).ToList());

    public static HojaExcel Bloqueos(IReadOnlyList<BloqueoHistorialDto> lista) => new("Bloqueos",
        ["Fecha", "Clase", "Tipo de bloqueo", "Etapa", "Entidad afectada", "Motivo", "Fecha de resolución", "Duración (h)", "Registró"],
        lista.Select(x => (IReadOnlyList<object?>)
        [
            x.Fecha, x.Clase == "bloqueo" ? "Bloqueo" : "Excepción", x.TipoNombre, x.EtapaNombre ?? x.Etapa, x.Entidad, x.Motivo,
            x.FechaResolucion, x.DuracionHoras, x.Usuario,
        ]).ToList());

    public static HojaExcel AlertasSla(IReadOnlyList<AlertaSlaHistorialDto> lista) => new("Alertas SLA",
        ["Fecha", "Etapa", "Nivel", "SLA establecido (h)", "SLA real (h)", "Desvío (h)", "Responsable", "Acción tomada"],
        lista.Select(x => (IReadOnlyList<object?>)
            [x.Fecha, x.EtapaNombre ?? x.Etapa, Nivel(x.Nivel), x.SlaHoras, x.HorasReales, x.DesvioHoras, x.Responsable, x.AccionTomada]).ToList());

    public static HojaExcel Documentos(IReadOnlyList<DocumentoExpedienteDto> lista) => new("Documentos",
        ["Nombre", "Tipo", "Categoría", "Origen", "Versión", "Estado", "Fecha de carga", "Usuario", "Formato"],
        lista.Select(d => (IReadOnlyList<object?>)
            [d.Nombre, d.Tipo, d.Categoria, d.Origen, d.Version, d.Estado, d.Fecha, d.Usuario, d.Formato]).ToList());
}

/// <summary>
/// HU-30 — Exportar Expediente Completo (ZIP): expediente.xlsx (resumen, etapas, entidades y auditoría) y los documentos
/// que el usuario puede ver, en una carpeta por categoría. Los PDF de las propuestas se generan y los correos de
/// seguimiento se arman como .eml. Lo que no esté en el almacenamiento va a "pendientes.txt" en vez de fallar.
/// El ZIP se arma en un archivo temporal (no en memoria) que se borra solo al terminar la descarga.
/// </summary>
public class ExportarExpedienteCasoDeUso(
    IExpedienteRepositorio       repositorio,
    IGeneradorExcel              excel,
    IAlmacenArchivos             almacen,
    GenerarPdfPropuestaCasoDeUso pdfPropuesta)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");

        var d = await repositorio.ObtenerDetalleAsync(idExpediente, idUsuario, ct);
        if (d.IdTipoMensaje != 2 || d.Datos is null) return new(d.IdTipoMensaje, d.Mensaje);
        var h = await repositorio.ObtenerHistorialAsync(idExpediente, new FiltrosHistorialExpedienteDto(), null, idUsuario, ct);
        if (h.IdTipoMensaje != 2 || h.Datos is null) return new(h.IdTipoMensaje, h.Mensaje);
        var archivos = await repositorio.ObtenerArchivosExportacionAsync(idExpediente, idUsuario, ct);
        if (archivos.IdTipoMensaje != 2 || archivos.Datos is null) return new(archivos.IdTipoMensaje, archivos.Mensaje);

        var numero = Limpiar(d.Datos.Cabecera.Numero);
        var temporal = new FileStream(Path.Combine(Path.GetTempPath(), $"tw-exp-{Guid.NewGuid():N}.zip"), FileMode.CreateNew,
                                      FileAccess.ReadWrite, FileShare.None, 81920, FileOptions.DeleteOnClose | FileOptions.Asynchronous);
        try
        {
            using (var zip = new ZipArchive(temporal, ZipArchiveMode.Create, leaveOpen: true))
            {
                var libro = excel.Generar(
                [
                    HojasExpediente.Resumen(d.Datos.Cabecera),
                    HojasExpediente.Etapas(d.Datos.Etapas),
                    HojasExpediente.Entidades(d.Datos.Entidades),
                    HojasExpediente.Timeline(h.Datos.Timeline),
                    HojasExpediente.Reasignaciones(h.Datos.Reasignaciones),
                    HojasExpediente.Bloqueos(h.Datos.Bloqueos),
                    HojasExpediente.AlertasSla(h.Datos.AlertasSla),
                ]);
                await EscribirAsync(zip, $"{numero}/expediente.xlsx", libro, ct);

                var pendientes = new List<string>();
                var usados = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var a in archivos.Datos)
                {
                    var carpeta = Limpiar(a.Carpeta);
                    var nombre  = Limpiar(a.Version > 1 && a.Correo is null
                        ? $"{Path.GetFileNameWithoutExtension(a.NombreArchivo)}-v{a.Version}{Path.GetExtension(a.NombreArchivo)}"
                        : a.NombreArchivo);
                    var ruta    = Unico($"{numero}/{carpeta}/{nombre}", usados);

                    if (a.Correo is { } correo)
                    {
                        await EscribirAsync(zip, ruta, ArchivoExpediente.Eml(correo), ct);
                        continue;
                    }
                    if (a.IdPropuesta is { } idPropuesta)
                    {
                        var pdf = await pdfPropuesta.EjecutarAsync(idPropuesta, ct);
                        if (pdf.IdTipoMensaje == 2 && pdf.Datos is not null) await EscribirAsync(zip, ruta, pdf.Datos, ct);
                        else pendientes.Add($"{carpeta}/{nombre}: {pdf.Mensaje}");
                        continue;
                    }

                    var contenido = a.Ruta is null ? null : await ArchivoExpediente.AbrirAsync(almacen, a.Ruta, ct);
                    if (contenido is null) { pendientes.Add($"{carpeta}/{nombre}: no se encontró en el almacenamiento."); continue; }
                    await using (contenido)
                    {
                        var entrada = zip.CreateEntry(ruta, CompressionLevel.Optimal);
                        await using var destino = entrada.Open();
                        await contenido.CopyToAsync(destino, ct);
                    }
                }

                if (pendientes.Count > 0)
                    await EscribirAsync(zip, $"{numero}/pendientes.txt",
                        Encoding.UTF8.GetBytes("Documentos que no se pudieron incluir:\r\n" + string.Join("\r\n", pendientes)), ct);
            }

            temporal.Position = 0;
            return new(2, "Expediente exportado.", new ArchivoDescargaDto(temporal, $"{numero}.zip", "application/zip"));
        }
        catch
        {
            await temporal.DisposeAsync();
            throw;
        }
    }

    private static async Task EscribirAsync(ZipArchive zip, string ruta, byte[] contenido, CancellationToken ct)
    {
        var entrada = zip.CreateEntry(ruta, CompressionLevel.Optimal);
        await using var destino = entrada.Open();
        await destino.WriteAsync(contenido, ct);
    }

    private static string Limpiar(string texto)
    {
        var limpio = ArchivoExpediente.NombreSeguro(texto);
        return limpio.Length == 0 ? "documento" : limpio;
    }

    private static string Unico(string ruta, HashSet<string> usados)
    {
        var candidata = ruta;
        for (var i = 2; !usados.Add(candidata); i++)
            candidata = $"{Path.ChangeExtension(ruta, null)} ({i}){Path.GetExtension(ruta)}";
        return candidata;
    }
}

// ── HU-31 Documentos ─────────────────────────────────────────────────────────

public class ObtenerDocumentosExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    private static readonly string[] Categorias = ["", "todos", "comerciales", "operativos", "ssoma", "tecnicos"];
    private static readonly string[] Formatos   = ["", "PDF", "XLSX", "DOCX", "EML", "JPG", "PNG", "OTRO"];

    public Task<RespuestaDto<DocumentosExpedienteDto>> EjecutarAsync(long idExpediente, FiltrosDocumentosExpedienteDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = Normalizar(idExpediente, f);
        return error is not null
            ? Task.FromResult(new RespuestaDto<DocumentosExpedienteDto>(1, error))
            : repositorio.ObtenerDocumentosAsync(idExpediente, filtros, false, idUsuario, ct);
    }

    internal static (FiltrosDocumentosExpedienteDto Filtros, string? Error) Normalizar(long idExpediente, FiltrosDocumentosExpedienteDto f)
    {
        if (idExpediente <= 0) return (f, "Expediente no válido.");
        var categoria = f.Categoria?.Trim().ToLowerInvariant() ?? "";
        if (!Categorias.Contains(categoria)) return (f, "Categoría no válida. Use todos, comerciales, operativos, ssoma o tecnicos.");
        var formato = f.Formato?.Trim().ToUpperInvariant() ?? "";
        if (!Formatos.Contains(formato)) return (f, "Formato no válido. Use PDF, XLSX, DOCX, EML, JPG, PNG u OTRO.");
        var orden = f.Orden?.Trim().ToLowerInvariant() ?? "";
        if (orden is not ("" or "asc" or "desc")) return (f, "Orden no válido. Use asc o desc.");
        if (f.Desde is { } d && f.Hasta is { } h && d.Date > h.Date) return (f, "La fecha desde no puede ser posterior a la fecha hasta.");

        return (f with
        {
            Categoria = categoria == "" ? null : categoria,
            Busqueda  = ArchivoExpediente.Recortar(f.Busqueda, 100),
            Desde     = f.Desde?.Date,
            Hasta     = f.Hasta?.Date,
            Estado    = ArchivoExpediente.Recortar(f.Estado, 30),
            Formato   = formato == "" ? null : formato,
            Orden     = orden == "" ? null : orden,
        }, null);
    }
}

/// <summary>HU-31 — Exportar lista XLSX: metadata de los documentos de la pestaña y filtros activos (no los archivos).</summary>
public class ExportarDocumentosExpedienteCasoDeUso(IExpedienteRepositorio repositorio, IGeneradorExcel excel)
{
    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(long idExpediente, FiltrosDocumentosExpedienteDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = ObtenerDocumentosExpedienteCasoDeUso.Normalizar(idExpediente, f);
        if (error is not null) return new(1, error);

        var r = await repositorio.ObtenerDocumentosAsync(idExpediente, filtros, true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        return new(2, "Lista de documentos exportada.",
            new ArchivoGeneradoDto(excel.Generar([HojasExpediente.Documentos(r.Datos.Documentos)]),
                                   $"Documentos-{ArchivoExpediente.NombreSeguro(r.Datos.Numero)}.xlsx", ArchivoExpediente.TipoXlsx));
    }
}

/// <summary>
/// Abre un documento del expediente para la vista previa o la descarga: archivo del almacenamiento, PDF de la propuesta
/// (se genera) o correo de seguimiento (.eml).
/// </summary>
public class ObtenerArchivoExpedienteCasoDeUso(
    IExpedienteRepositorio       repositorio,
    IAlmacenArchivos             almacen,
    GenerarPdfPropuestaCasoDeUso pdfPropuesta)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idExpediente, string clave, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0 || string.IsNullOrWhiteSpace(clave) || clave.Trim().Length > 40) return new(1, "Documento no válido.");

        var u = await repositorio.ObtenerArchivoAsync(idExpediente, clave.Trim().ToLowerInvariant(), idUsuario, ct);
        if (u.IdTipoMensaje != 2 || u.Datos is null) return new(u.IdTipoMensaje, u.Mensaje);

        if (u.Datos.Correo is { } correo)
            return new(2, u.Mensaje, new ArchivoDescargaDto(new MemoryStream(ArchivoExpediente.Eml(correo)), u.Datos.NombreArchivo,
                                                             ArchivoExpediente.TipoEml));

        if (u.Datos.IdPropuesta is { } idPropuesta)
        {
            var pdf = await pdfPropuesta.EjecutarAsync(idPropuesta, ct);
            if (pdf.IdTipoMensaje != 2 || pdf.Datos is null) return new(pdf.IdTipoMensaje, pdf.Mensaje);
            return new(2, u.Mensaje, new ArchivoDescargaDto(new MemoryStream(pdf.Datos), u.Datos.NombreArchivo, ArchivoExpediente.TipoPdf));
        }

        var contenido = u.Datos.Ruta is null ? null : await ArchivoExpediente.AbrirAsync(almacen, u.Datos.Ruta, ct);
        if (contenido is null)
            return new(1, "El documento está registrado pero el archivo no se encontró en el almacenamiento.");

        var tipo = u.Datos.TipoContenido ?? ArchivoExpediente.TipoContenido(Path.GetExtension(u.Datos.NombreArchivo).ToLowerInvariant());
        return new(2, u.Mensaje, new ArchivoDescargaDto(contenido, u.Datos.NombreArchivo, tipo));
    }
}

// ── HU-32 Historial de auditoría ─────────────────────────────────────────────

public class ObtenerHistorialExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<HistorialExpedienteDto>> EjecutarAsync(long idExpediente, FiltrosHistorialExpedienteDto f, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0)
            return Task.FromResult(new RespuestaDto<HistorialExpedienteDto>(1, "Expediente no válido."));
        if (f.Desde is { } d && f.Hasta is { } h && d.Date > h.Date)
            return Task.FromResult(new RespuestaDto<HistorialExpedienteDto>(1, "La fecha desde no puede ser posterior a la fecha hasta."));
        return repositorio.ObtenerHistorialAsync(idExpediente, Normalizar(f), null, idUsuario, ct);
    }

    internal static FiltrosHistorialExpedienteDto Normalizar(FiltrosHistorialExpedienteDto f) => f with
    {
        Busqueda   = ArchivoExpediente.Recortar(f.Busqueda, 100),
        IdUsuario  = f.IdUsuario is > 0 ? f.IdUsuario : null,
        Etapa      = ArchivoExpediente.Codigo(f.Etapa, 30),
        TipoEvento = ArchivoExpediente.Codigo(f.TipoEvento, 30),
        Desde      = f.Desde?.Date,
        Hasta      = f.Hasta?.Date,
    };
}

/// <summary>
/// HU-32 — Exporta el tab activo (timeline, reasignaciones, bloqueos o alertas_sla) con los filtros aplicados, en XLSX o PDF.
/// La exportación queda registrada en la auditoría del expediente.
/// </summary>
public class ExportarHistorialExpedienteCasoDeUso(IExpedienteRepositorio repositorio, IGeneradorExcel excel, IGeneradorPdfTabla pdf)
{
    private static readonly string[] Tabs = ["timeline", "reasignaciones", "bloqueos", "alertas_sla"];

    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(
        long idExpediente, string? tab, string? formato, FiltrosHistorialExpedienteDto f, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        var t = string.IsNullOrWhiteSpace(tab) ? "timeline" : tab.Trim().ToLowerInvariant();
        if (!Tabs.Contains(t)) return new(1, "Tab no válido. Use timeline, reasignaciones, bloqueos o alertas_sla.");
        var fmt = string.IsNullOrWhiteSpace(formato) ? "xlsx" : formato.Trim().ToLowerInvariant();
        if (fmt is not ("xlsx" or "pdf")) return new(1, "Formato no válido. Use xlsx o pdf.");
        if (f.Desde is { } d && f.Hasta is { } h && d.Date > h.Date) return new(1, "La fecha desde no puede ser posterior a la fecha hasta.");

        var r = await repositorio.ObtenerHistorialAsync(idExpediente, ObtenerHistorialExpedienteCasoDeUso.Normalizar(f), t, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var hoja = t switch
        {
            "reasignaciones" => HojasExpediente.Reasignaciones(r.Datos.Reasignaciones),
            "bloqueos"       => HojasExpediente.Bloqueos(r.Datos.Bloqueos),
            "alertas_sla"    => HojasExpediente.AlertasSla(r.Datos.AlertasSla),
            _                => HojasExpediente.Timeline(r.Datos.Timeline),
        };
        var numero = ArchivoExpediente.NombreSeguro(r.Datos.Numero);
        var nombre = $"Auditoria-{numero}-{t}";

        if (fmt == "pdf")
        {
            var documento = new DocumentoTablaPdf(
                $"Historial de Auditoría — {hoja.Nombre}",
                $"{r.Datos.Numero} · {r.Datos.RazonSocial} · Responsable: {r.Datos.Responsable ?? "—"}",
                hoja, $"Exportado el {DateTime.Now:dd/MM/yyyy HH:mm} · {hoja.Filas.Count} registros");
            return new(2, "Auditoría exportada.", new ArchivoGeneradoDto(pdf.Generar(documento), $"{nombre}.pdf", ArchivoExpediente.TipoPdf));
        }
        return new(2, "Auditoría exportada.", new ArchivoGeneradoDto(excel.Generar([hoja]), $"{nombre}.xlsx", ArchivoExpediente.TipoXlsx));
    }
}

// ── HU-33 Reasignación ───────────────────────────────────────────────────────

public class PrepararReasignacionExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionReasignacionExpedienteDto>> EjecutarAsync(long idExpediente, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionReasignacionExpedienteDto>(1, "Expediente no válido."))
            : repositorio.PrepararReasignacionAsync(idExpediente, idUsuario, ct);
}

/// <summary>HU-33 Opción C — Impacto global de la cartera activa del comercial.</summary>
public class ObtenerCarteraComercialExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<CarteraComercialExpedienteDto>> EjecutarAsync(long idExpediente, long? idResponsable, long idUsuario, CancellationToken ct = default)
        => idExpediente <= 0
            ? Task.FromResult(new RespuestaDto<CarteraComercialExpedienteDto>(1, "Expediente no válido."))
            : repositorio.ObtenerCarteraComercialAsync(idExpediente, idResponsable is > 0 ? idResponsable : null, idUsuario, ct);
}

/// <summary>HU-33 — Buscador del nuevo responsable (rol Comercial).</summary>
public class BuscarResponsablesExpedienteCasoDeUso(IExpedienteRepositorio repositorio)
{
    public Task<RespuestaDto<IReadOnlyList<CandidatoResponsableDto>>> EjecutarAsync(string? busqueda, long? idExcluir, long idUsuario, CancellationToken ct = default)
        => repositorio.BuscarResponsablesAsync(ArchivoExpediente.Recortar(busqueda, 100), idExcluir is > 0 ? idExcluir : null, idUsuario, ct);
}

/// <summary>
/// HU-33 — Confirma la reasignación (entidad, cascada o global). El SP registra el detalle, los timelines de cada entidad,
/// el evento consolidado de cada expediente y las notificaciones en la intranet; aquí se envían los correos al nuevo
/// responsable (lista de lo que ahora es suyo) y a los anteriores (informativo). Si un correo falla, la reasignación se
/// mantiene y se informa en la respuesta.
/// </summary>
public class ReasignarResponsableExpedienteCasoDeUso(
    IExpedienteRepositorio repositorio,
    NotificadorCorreo      notificador,
    OpcionesCorreo         opciones)
{
    private static readonly string[] Modos    = ["entidad", "cascada", "global"];
    private static readonly string[] Tipos    = ["requerimiento", "propuesta", "orden_compra", "orden_servicio"];
    private static readonly string[] Gestiones = ["mantener", "reiniciar"];

    public async Task<RespuestaDto<ReasignacionExpedienteDto>> EjecutarAsync(
        long idExpediente, ReasignarResponsableExpedienteDto datos, long idUsuario, CancellationToken ct = default)
    {
        if (idExpediente <= 0) return new(1, "Expediente no válido.");
        var modo = datos.Modo?.Trim().ToLowerInvariant() ?? "";
        if (!Modos.Contains(modo)) return new(1, "Elija el tipo de reasignación: entidad, cascada o global.");
        var tipo = datos.EntidadTipo?.Trim().ToLowerInvariant();
        if (modo != "global" && (tipo is null || !Tipos.Contains(tipo) || datos.IdEntidad is not > 0))
            return new(1, "Seleccione la entidad a reasignar (RQ, propuesta, OC u OS).");
        if (datos.IdNuevoResponsable is not > 0) return new(1, "Seleccione el nuevo responsable.");
        if (datos.IdMotivo is not > 0) return new(1, "Seleccione el motivo de la reasignación.");
        var comentario = datos.Comentario?.Trim() ?? "";
        if (comentario.Length < 20) return new(1, "El comentario es obligatorio (mínimo 20 caracteres).");
        if (comentario.Length > 1000) return new(1, "El comentario no puede superar los 1000 caracteres.");
        var gestion = datos.GestionSla?.Trim().ToLowerInvariant() ?? "";
        if (!Gestiones.Contains(gestion)) return new(1, "Indique la gestión del SLA: mantener o reiniciar.");
        var excluidos = modo == "cascada"
            ? datos.Excluidos?.Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x.Trim().ToLowerInvariant())
                   .Where(x => x.Length <= 40).Distinct().Take(500).ToList()
            : null;

        var r = await repositorio.ReasignarResponsableAsync(idExpediente, datos with
        {
            Modo = modo, EntidadTipo = modo == "global" ? null : tipo, IdEntidad = modo == "global" ? null : datos.IdEntidad,
            Excluidos = excluidos, Comentario = comentario, GestionSla = gestion,
            IdResponsableActual = modo == "global" && datos.IdResponsableActual is > 0 ? datos.IdResponsableActual : null,
        }, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return r;

        var enviados = 0;
        var errores  = new List<string>();
        if (!string.IsNullOrWhiteSpace(r.Datos.CorreoResponsable))
        {
            var envio = await notificador.EnviarAsync("expediente_reasignado", PlantillasCorreo.ResponsableAsignado(r.Datos, opciones),
                                                      "expediente", idExpediente, idUsuario, ct);
            if (envio.Enviado) enviados++; else errores.Add($"{r.Datos.Responsable}: {envio.Error}");
        }
        foreach (var anterior in r.Datos.ResponsablesAnteriores.Where(a => !string.IsNullOrWhiteSpace(a.Correo)))
        {
            var envio = await notificador.EnviarAsync("expediente_reasignado_aviso",
                PlantillasCorreo.ResponsableReemplazado(r.Datos, anterior, opciones), "expediente", idExpediente, idUsuario, ct);
            if (envio.Enviado) enviados++; else errores.Add($"{anterior.Nombre}: {envio.Error}");
        }

        var mensaje = errores.Count == 0
            ? r.Mensaje
            : $"{r.Mensaje} No se pudieron enviar {errores.Count} correo(s); se notificó en la intranet.";
        return new(2, mensaje, r.Datos with { CorreosEnviados = enviados, CorreosConError = errores });
    }
}
