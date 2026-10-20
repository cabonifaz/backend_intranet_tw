using System.Globalization;
using System.Security.Cryptography;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═════════════════════════════════════════════════════════════════════════════
// Órdenes de Compra — Sprint 4 (refinamiento HU-22 a HU-28)
// La IA (Gemini) lee el PDF y evalúa los conceptos; las reglas de la BD comparan los campos estructurados
// y deciden qué se puede hacer. Sin IA configurada todo funciona con carga manual y validación por reglas.
// ═════════════════════════════════════════════════════════════════════════════

/// <summary>Lectura y verificación del PDF de la OC.</summary>
internal static class PdfOrdenCompra
{
    public const long TamanoMaximoBytes = 10 * 1024 * 1024;

    /// <summary>Copia el archivo al buffer y verifica tamaño y firma "%PDF-" (no basta con la extensión). Devuelve el error o null.</summary>
    public static async Task<string?> LeerAsync(Stream pdf, MemoryStream buffer, CancellationToken ct)
    {
        await pdf.CopyToAsync(buffer, ct);
        if (buffer.Length == 0)                return "Adjunte el PDF de la orden de compra.";
        if (buffer.Length > TamanoMaximoBytes) return "El PDF de la orden de compra no puede superar los 10 MB.";
        if (!buffer.GetBuffer().AsSpan(0, (int)buffer.Length).StartsWith("%PDF-"u8))
            return "El archivo de la orden de compra no es un PDF válido.";
        return null;
    }

    public static string Hash(MemoryStream buffer) =>
        Convert.ToHexStringLower(SHA256.HashData(buffer.GetBuffer().AsSpan(0, (int)buffer.Length)));

    public static string Ruta(string carpeta) =>
        $"ordenes-compra/{carpeta}/{DateTime.Now:yyyyMMddHHmmss}_{Guid.NewGuid():N}.pdf";

    /// <summary>Las OC antiguas pueden tener una URL externa en vez de una ruta interna: se responde como archivo no encontrado.</summary>
    public static async Task<Stream?> AbrirAsync(IAlmacenArchivos almacen, string ruta, CancellationToken ct)
    {
        try { return await almacen.AbrirLecturaAsync(ruta, ct); }
        catch (InvalidOperationException) { return null; }
        catch (ArgumentException) { return null; }
    }

    public static string NormalizarNombre(string? nombreArchivo, string numeroOc)
    {
        var nombre = Path.GetFileName(nombreArchivo ?? "").Trim();
        foreach (var c in Path.GetInvalidFileNameChars())
            nombre = nombre.Replace(c, '_');
        if (nombre.Length == 0) nombre = $"OC-{numeroOc}.pdf";
        if (!nombre.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)) nombre += ".pdf";
        if (nombre.Length > 255) nombre = nombre[..251] + ".pdf";
        return nombre;
    }

    /// <summary>Guarda el PDF ya verificado en el almacenamiento.</summary>
    public static async Task<ArchivoPdfOcDto> GuardarAsync(IAlmacenArchivos almacen, MemoryStream buffer, string carpeta,
                                                          string? nombreArchivo, string numeroOc, CancellationToken ct)
    {
        var ruta = Ruta(carpeta);
        var hash = Hash(buffer);
        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);
        return new ArchivoPdfOcDto(ruta, NormalizarNombre(nombreArchivo, numeroOc), buffer.Length, hash);
    }
}

/// <summary>Limpieza de los datos de la ficha antes de enviarlos a la BD (que vuelve a validarlo todo).</summary>
internal static class DatosOrdenCompra
{
    private static string? Limpio(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        return s.Length > max ? s[..max] : s;
    }

    public static DatosOrdenCompraDto Normalizar(DatosOrdenCompraDto? d)
    {
        d ??= new DatosOrdenCompraDto();
        return new DatosOrdenCompraDto
        {
            NumeroOc        = d.NumeroOc?.Trim(),
            FechaEmision    = d.FechaEmision?.Date,
            FechaRecepcion  = d.FechaRecepcion?.Date,
            IdMoneda        = d.IdMoneda is > 0 ? d.IdMoneda : null,
            MontoTotal      = d.MontoTotal is { } m ? Math.Round(m, 2) : null,
            IdCondicionPago = d.IdCondicionPago is > 0 ? d.IdCondicionPago : null,
            FormaPago       = Limpio(d.FormaPago, 150),
            IgvIncluido     = d.IgvIncluido,
            IgvPct          = d.IgvPct,
            Descuento       = d.Descuento is { } ds ? Math.Round(ds, 2) : null,
            Ruc             = Limpio(d.Ruc, 20),
            RazonSocial     = Limpio(d.RazonSocial, 250),
            NumeroPropuesta = Limpio(d.NumeroPropuesta, 50),
            VigenciaHasta   = d.VigenciaHasta?.Date,
            Referencia      = d.Referencia?.Trim() is { Length: > 0 } r ? r : null,
            Observaciones   = d.Observaciones?.Trim() is { Length: > 0 } o ? o : null,
            FacturaIgualOc  = d.FacturaIgualOc,
            Conceptos       = (d.Conceptos ?? [])
                .Where(c => !string.IsNullOrWhiteSpace(c.Descripcion))
                .Take(200)
                .Select(c => new ConceptoOrdenCompraDto
                {
                    Descripcion    = Limpio(c.Descripcion, 300)!,
                    Cantidad       = c.Cantidad,
                    PrecioUnitario = c.PrecioUnitario,
                    Subtotal       = c.Subtotal is { } st ? Math.Round(st, 2) : null,
                })
                .ToList(),
            CamposIa        = d.CamposIa is { Count: > 0 } ? d.CamposIa : null,
            CamposManuales  = (d.CamposManuales ?? []).Where(c => !string.IsNullOrWhiteSpace(c.Campo)).Take(50).ToList(),
        };
    }

    public static List<VinculacionOrdenCompraDto> Vinculaciones(List<VinculacionOrdenCompraDto>? v) =>
        (v ?? []).Select(x => new VinculacionOrdenCompraDto { IdPropuesta = x.IdPropuesta, MontoAsignado = Math.Round(x.MontoAsignado, 2) }).ToList();

    public static string? Decision(string? d) =>
        string.IsNullOrWhiteSpace(d) ? null : d.Trim().ToLowerInvariant();
}

/// <summary>
/// Evaluación de la IA por propuesta vinculada: los conceptos de la OC contra los ítems de cada propuesta,
/// con las diferencias de las reglas como contexto. Si la IA no está o falla, devuelve un aviso y el
/// guardado sigue con las reglas.
/// </summary>
internal static class EvaluacionIaOrdenCompra
{
    public sealed record PropuestaAEvaluar(long IdPropuesta, string Numero);

    public static async Task<(List<EvaluacionIaPropuestaDto>? Evaluaciones, string? Aviso)> EvaluarAsync(
        IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia,
        IReadOnlyList<ConceptoOrdenCompraDto> conceptos, int? idMoneda, bool facturaIgualOc,
        IReadOnlyList<PropuestaAEvaluar> propuestas, IReadOnlyList<CampoComparadoOcDto> diferencias,
        long idUsuario, CancellationToken ct)
    {
        if (!ia.Disponible)       return (null, "IA no configurada: la OC se validó solo con reglas.");
        if (conceptos.Count == 0) return (null, null);
        if (propuestas.Count == 0) return (null, null);

        var datos = await repositorio.ObtenerDatosIaAsync(propuestas.Select(p => p.IdPropuesta).ToList(), idUsuario, ct);
        if (datos.IdTipoMensaje != 2 || datos.Datos is null)
            return (null, "No se pudieron leer los ítems de las propuestas para la IA: se validó solo con reglas.");

        var simbolo = datos.Datos.Monedas.FirstOrDefault(m => m.Id == idMoneda)?.Simbolo;
        var varias  = propuestas.Count > 1;

        var tareas = propuestas.Select(async p =>
        {
            var items = datos.Datos.Items.Where(i => i.IdPropuesta == p.IdPropuesta).ToList();
            if (items.Count == 0) return (p, new ResultadoIa<EvaluacionIaPropuestaDto>(null, null));
            var solicitud = new SolicitudEvaluacionIaDto(p.IdPropuesta, p.Numero, simbolo, conceptos, items,
                diferencias.Where(d => d.IdPropuesta == p.IdPropuesta).ToList(), facturaIgualOc, varias);
            return (p, await ia.EvaluarAsync(solicitud, ct));
        });
        var resultados = await Task.WhenAll(tareas);

        var evaluaciones = resultados.Where(r => r.Item2.Ok).Select(r => r.Item2.Datos!).ToList();
        var errores = resultados.Where(r => r.Item2.Error is not null).ToList();
        string? aviso = errores.Count == 0
            ? null
            : $"{errores[0].Item2.Error} Propuesta(s) validada(s) solo con reglas: {string.Join(", ", errores.Select(e => e.p.Numero))}.";
        return (evaluaciones.Count > 0 ? evaluaciones : null, aviso);
    }

    /// <summary>
    /// "Generar nueva versión de propuesta": crea la versión nueva de cada propuesta observada con ese tipo y la
    /// vincula a la OC. Los errores no deshacen el guardado: se informan por propuesta.
    /// </summary>
    public static async Task<List<NuevaVersionGeneradaOcDto>> GenerarNuevasVersionesAsync(
        IOrdenCompraRepositorio repositorio, IPropuestasRepositorio propuestas, ResultadoGuardarOrdenCompraDto guardado,
        long idUsuario, CancellationToken ct)
    {
        var pendientes = guardado.Vinculaciones
            .Where(v => v.TipoObservacion == "nueva_version" && v.IdPropuestaNuevaVersion is null)
            .ToList();
        var generadas = new List<NuevaVersionGeneradaOcDto>();
        if (pendientes.Count == 0) return generadas;

        var datos = await repositorio.ObtenerDatosIaAsync([], idUsuario, CancellationToken.None);
        var idMotivo = datos.Datos?.IdMotivoNuevaVersion;
        if (idMotivo is null)
            return pendientes.Select(v => new NuevaVersionGeneradaOcDto(v.IdPropuesta, null, null, null,
                "No está configurado el motivo de nueva versión (SOLICITUD_CLIENTE).")).ToList();

        foreach (var v in pendientes)
        {
            var nueva = await propuestas.CrearNuevaVersionAsync(v.IdPropuesta, new CrearNuevaVersionPropuestaDto
            {
                IdMotivoNuevaVersion = idMotivo.Value,
                DescripcionCambios   = $"Ajuste de conceptos según la OC {guardado.Oc.NumeroOc} del cliente.",
            }, idUsuario, CancellationToken.None);

            if (nueva.IdTipoMensaje != 2 || nueva.Datos is null)
            {
                generadas.Add(new NuevaVersionGeneradaOcDto(v.IdPropuesta, null, null, null, nueva.Mensaje));
                continue;
            }

            var vinculo = await repositorio.VincularNuevaVersionAsync(guardado.Oc.IdOc, v.IdPropuesta, nueva.Datos.IdPropuesta,
                                                                     idUsuario, CancellationToken.None);
            generadas.Add(new NuevaVersionGeneradaOcDto(v.IdPropuesta, nueva.Datos.IdPropuesta, nueva.Datos.Numero, nueva.Datos.Version,
                vinculo.IdTipoMensaje == 2 ? null : vinculo.Mensaje));
        }
        return generadas;
    }

    public static string? UnirAvisos(params string?[] avisos)
    {
        var lista = avisos.Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
        return lista.Count == 0 ? null : string.Join(" ", lista);
    }
}

// ══════════════════════ Bandeja, detalle, modal de validación y timeline ══════════════════════

/// <summary>Bandeja consolidada: tarjetas, monto validado del mes, filas y opciones de filtro.</summary>
public class ObtenerBandejaOrdenesCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    private static readonly string[] Estados =
        ["", "todas", "recibida", "validada", "validada_parcial", "observada", "anulada", "reemplazada", "autogeneradas", "sin_asignar"];

    public Task<RespuestaDto<BandejaOrdenesCompraDto>> EjecutarAsync(FiltrosBandejaOrdenesCompraDto f, long idUsuario, CancellationToken ct = default)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return Task.FromResult(new RespuestaDto<BandejaOrdenesCompraDto>(1,
                "Estado no válido. Use todas, recibida, validada, validada_parcial, observada, anulada, reemplazada, autogeneradas o sin_asignar."));
        if (f.FechaDesde is { } desde && f.FechaHasta is { } hasta && desde.Date > hasta.Date)
            return Task.FromResult(new RespuestaDto<BandejaOrdenesCompraDto>(1, "La fecha desde no puede ser posterior a la fecha hasta."));

        var filtros = new FiltrosBandejaOrdenesCompraDto
        {
            Estado        = estado,
            IdCliente     = f.IdCliente     is > 0 ? f.IdCliente     : null,
            IdResponsable = f.IdResponsable is > 0 ? f.IdResponsable : null,
            IdPropuesta   = f.IdPropuesta   is > 0 ? f.IdPropuesta   : null,
            FechaDesde    = f.FechaDesde?.Date,
            FechaHasta    = f.FechaHasta?.Date,
            Busqueda      = string.IsNullOrWhiteSpace(f.Busqueda) ? null : f.Busqueda.Trim()[..Math.Min(f.Busqueda.Trim().Length, 200)],
            Pagina        = Math.Max(1, f.Pagina),
            PorPagina     = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina,
        };
        return repositorio.ObtenerBandejaAsync(filtros, idUsuario, ct);
    }
}

/// <summary>Detalle: cabecera con datos extraídos, propuestas vinculadas con su validación y diferencias.</summary>
public class ObtenerDetalleOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleOrdenCompraDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default) =>
        idOc <= 0
            ? Task.FromResult(new RespuestaDto<DetalleOrdenCompraDto>(1, "Orden de compra no válida."))
            : repositorio.ObtenerDetalleAsync(idOc, idUsuario, ct);
}

/// <summary>Modal "Detalle de Validación IA" de una propuesta vinculada (por defecto, la primera).</summary>
public class ObtenerValidacionOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<ValidacionOrdenCompraDto>> EjecutarAsync(long idOc, long? idPropuesta, long idUsuario, CancellationToken ct = default) =>
        idOc <= 0
            ? Task.FromResult(new RespuestaDto<ValidacionOrdenCompraDto>(1, "Orden de compra no válida."))
            : repositorio.ObtenerValidacionAsync(idOc, idPropuesta is > 0 ? idPropuesta : null, idUsuario, ct);
}

/// <summary>Timeline de la OC (validación IA, gestión comercial y documental).</summary>
public class ObtenerTimelineOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<TimelineOrdenCompraDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default) =>
        idOc <= 0
            ? Task.FromResult(new RespuestaDto<TimelineOrdenCompraDto>(1, "Orden de compra no válida."))
            : repositorio.ObtenerTimelineAsync(idOc, registrarExportacion: false, idUsuario, ct);
}

/// <summary>Descarga el timeline en XLSX (la descarga queda registrada).</summary>
public class ExportarTimelineOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IGeneradorExcel excel)
{
    public const string TipoXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        var r = await repositorio.ObtenerTimelineAsync(idOc, registrarExportacion: true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var c = r.Datos.Cabecera;
        var hojas = new List<HojaExcel>
        {
            new("Resumen", ["Campo", "Valor"],
            [
                ["Orden de compra",  c.NumeroOc],
                ["Estado",           (c.EstadoVisual ?? c.Estado).Replace('_', ' ')],
                ["Autogenerada",     c.EsAutogenerada ? "Sí" : "No"],
                ["Cliente",          c.RazonSocial],
                ["RUC",              c.Ruc],
                ["Propuesta",        c.NumeroPropuesta is null ? null : $"{c.NumeroPropuesta} v{c.VersionPropuesta}"],
                ["Generado el",      c.GeneradoEn],
                ["Generado por",     c.GeneradoPor],
            ]),
            new("Timeline", ["Fecha", "Categoría", "Evento", "Detalle", "Estado anterior", "Estado nuevo", "Usuario", "Área", "Rol", "Automático (IA)"],
                r.Datos.Eventos.Select(e => (IReadOnlyList<object?>)
                    [e.Fecha, e.Categoria.Replace('_', ' '), e.Titulo, e.Descripcion, e.EstadoAnterior, e.EstadoNuevo,
                     e.Usuario, e.Area, e.Rol, e.AutomaticoIa ? "Sí" : "No"]).ToList()),
        };

        var nombre = $"Timeline_{Seguro(c.NumeroOc)}_{DateTime.Now:yyyyMMdd_HHmm}.xlsx";
        return new(2, "Timeline generado.", new ArchivoDescargaDto(new MemoryStream(excel.Generar(hojas)), nombre, TipoXlsx));
    }

    private static string Seguro(string texto)
    {
        foreach (var ch in Path.GetInvalidFileNameChars()) texto = texto.Replace(ch, '_');
        return texto.Replace(' ', '_');
    }
}

/// <summary>Abre el PDF de la orden de compra para verlo o descargarlo.</summary>
public class ObtenerPdfOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        var ruta = await repositorio.ObtenerRutaPdfAsync(idOc, idUsuario, ct);
        if (ruta.IdTipoMensaje != 2 || ruta.Datos is null) return new(ruta.IdTipoMensaje, ruta.Mensaje);

        var contenido = await PdfOrdenCompra.AbrirAsync(almacen, ruta.Datos.Ruta, ct);
        if (contenido is null)
            return new(1, "El PDF de la orden de compra está registrado pero no se encontró en el almacenamiento.");

        return new(2, ruta.Mensaje, new ArchivoDescargaDto(contenido, ruta.Datos.NombreArchivo, "application/pdf"));
    }
}

// ══════════════════════ Ficha: preparar, propuestas disponibles y extracción con IA ══════════════════════

/// <summary>Ficha de registro: propuesta de origen, OC autogenerada a reemplazar, otras propuestas y catálogos.</summary>
public class PrepararOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia)
{
    public async Task<RespuestaDto<PreparacionOrdenCompraDto>> EjecutarAsync(long idPropuesta, long? idOcReemplaza, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0) return new(1, "Propuesta no válida.");
        var r = await repositorio.PrepararAsync(idPropuesta, idOcReemplaza is > 0 ? idOcReemplaza : null, idUsuario, ct);
        return r.Datos is null ? r : r with { Datos = r.Datos with { ExtraccionIaDisponible = ia.Disponible } };
    }
}

/// <summary>Ficha en modo edición.</summary>
public class PrepararEdicionOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia)
{
    public async Task<RespuestaDto<PreparacionEdicionOrdenCompraDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        var r = await repositorio.PrepararEdicionAsync(idOc, idUsuario, ct);
        return r.Datos is null ? r : r with { Datos = r.Datos with { ExtraccionIaDisponible = ia.Disponible } };
    }
}

/// <summary>Propuestas aceptadas con saldo: "+ Nueva OC" (sin cliente) y "Agregar propuesta vinculada" (del cliente).</summary>
public class ObtenerPropuestasDisponiblesOcCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<List<PropuestaDisponibleOcDto>>> EjecutarAsync(long? idCliente, long? idOc, string? busqueda,
                                                                             long idUsuario, CancellationToken ct = default)
    {
        var texto = string.IsNullOrWhiteSpace(busqueda) ? null : busqueda.Trim();
        if (texto is { Length: > 200 }) texto = texto[..200];
        return repositorio.ObtenerPropuestasDisponiblesAsync(idCliente is > 0 ? idCliente : null, idOc is > 0 ? idOc : null,
                                                             texto, idUsuario, ct);
    }
}

/// <summary>
/// Lee el PDF con la IA y devuelve los datos para precargar la ficha (no guarda nada). La moneda y la condición
/// de pago se traducen al catálogo; los campos leídos van en CamposIa (se muestran bloqueados con el ícono IA).
/// </summary>
public class ExtraerOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia)
{
    public async Task<RespuestaDto<ExtraccionOrdenCompraDto>> EjecutarAsync(Stream? pdf, long idUsuario, CancellationToken ct = default)
    {
        if (pdf is null) return new(1, "Adjunte el PDF de la orden de compra.");
        if (!ia.Disponible) return new(1, "La extracción con IA no está configurada. Complete los datos de la OC manualmente.");

        using var buffer = new MemoryStream();
        if (await PdfOrdenCompra.LeerAsync(pdf, buffer, ct) is { } errorPdf) return new(1, errorPdf);

        var catalogos = await repositorio.ObtenerDatosIaAsync([], idUsuario, ct);
        if (catalogos.IdTipoMensaje != 2 || catalogos.Datos is null) return new(catalogos.IdTipoMensaje, catalogos.Mensaje);

        var leido = await ia.ExtraerAsync(buffer.ToArray(), ct);
        if (!leido.Ok) return new(1, leido.Error ?? "La IA no pudo leer la orden de compra. Complete los datos manualmente.");
        var e = leido.Datos!;

        var advertencias = new List<string>();
        var moneda = BuscarMoneda(catalogos.Datos.Monedas, e.Moneda);
        if (e.Moneda is not null && moneda is null)
            advertencias.Add($"La moneda leída ({e.Moneda}) no está en el catálogo: selecciónela manualmente.");

        var condicion = catalogos.Datos.CondicionesPago.FirstOrDefault(c =>
                            e.CondicionPagoCodigo is not null && string.Equals(c.Codigo, e.CondicionPagoCodigo, StringComparison.OrdinalIgnoreCase))
                        ?? catalogos.Datos.CondicionesPago.FirstOrDefault(c =>
                            e.FormaPago is not null && string.Equals(c.Nombre, e.FormaPago, StringComparison.OrdinalIgnoreCase));
        if (e.Confianza is < 70)
            advertencias.Add("La lectura del PDF tiene baja confianza: revise los datos antes de guardar.");
        if (e.Conceptos.Count == 0)
            advertencias.Add("La IA no encontró conceptos en la OC: la comparación de conceptos se hará por reglas.");

        var camposIa = new Dictionary<string, string?>();
        void Agregar(string campo, object? valor)
        {
            if (valor is null) return;
            camposIa[campo] = valor switch
            {
                DateTime f => f.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                decimal d  => d.ToString(CultureInfo.InvariantCulture),
                bool b     => b ? "true" : "false",
                _          => valor.ToString(),
            };
        }
        Agregar("numeroOc", e.NumeroOc);
        Agregar("fechaEmision", e.FechaEmision);
        Agregar("ruc", e.Ruc);
        Agregar("razonSocial", e.RazonSocial);
        Agregar("numeroPropuesta", e.NumeroPropuesta);
        Agregar("idMoneda", moneda?.Id);
        Agregar("montoTotal", e.MontoTotal);
        Agregar("formaPago", e.FormaPago);
        Agregar("idCondicionPago", condicion?.Id);
        Agregar("igvIncluido", e.IgvIncluido);
        Agregar("igvPct", e.IgvPct);
        Agregar("descuento", e.Descuento);
        Agregar("vigenciaHasta", e.VigenciaHasta);
        if (e.Conceptos.Count > 0) camposIa["conceptos"] = e.Conceptos.Count.ToString(CultureInfo.InvariantCulture);

        var datos = new DatosOrdenCompraDto
        {
            NumeroOc        = e.NumeroOc,
            FechaEmision    = e.FechaEmision,
            IdMoneda        = moneda?.Id,
            MontoTotal      = e.MontoTotal is { } m ? Math.Round(m, 2) : null,
            IdCondicionPago = condicion?.Id,
            FormaPago       = e.FormaPago,
            IgvIncluido     = e.IgvIncluido,
            IgvPct          = e.IgvPct,
            Descuento       = e.Descuento,
            Ruc             = e.Ruc,
            RazonSocial     = e.RazonSocial,
            NumeroPropuesta = e.NumeroPropuesta,
            VigenciaHasta   = e.VigenciaHasta,
            FacturaIgualOc  = true,
            Conceptos       = e.Conceptos,
            CamposIa        = camposIa,
        };
        return new(2, "Datos leídos del PDF por la IA. Revíselos antes de guardar.",
            new ExtraccionOrdenCompraDto(datos, e.Moneda, e.Confianza, ia.Motor, advertencias));
    }

    private static MonedaOrdenCompraDto? BuscarMoneda(List<MonedaOrdenCompraDto> monedas, string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var t = texto.Trim();
        if (t is "S/" or "S/." or "SOLES" or "SOL") t = "PEN";
        if (t is "US$" or "DOLARES" or "DÓLARES" or "USD$") t = "USD";
        return monedas.FirstOrDefault(m => string.Equals(m.Codigo, t, StringComparison.OrdinalIgnoreCase))
            ?? monedas.FirstOrDefault(m => string.Equals(m.Simbolo, t, StringComparison.OrdinalIgnoreCase))
            ?? monedas.FirstOrDefault(m => m.Nombre.Contains(t, StringComparison.OrdinalIgnoreCase));
    }
}

// ══════════════════════ Validación y guardado ══════════════════════

/// <summary>
/// Validación en vivo de la ficha (no guarda): reglas por propuesta, sugerencia y qué decisiones se pueden tomar.
/// Con conIa = true también evalúa los conceptos con la IA (consume cuota: usar al pulsar "Validar", no en cada tecla).
/// </summary>
public class CompararOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia)
{
    public async Task<RespuestaDto<ComparacionOrdenCompraDto>> EjecutarAsync(CompararOrdenCompraSolicitudDto s, bool conIa,
                                                                             long idUsuario, CancellationToken ct = default)
    {
        if (s.IdOc is not > 0 && s.IdPropuesta is not > 0)
            return new(1, "Indique la propuesta de origen o la orden de compra que se edita.");

        var solicitud = new CompararOrdenCompraSolicitudDto
        {
            IdOc          = s.IdOc is > 0 ? s.IdOc : null,
            IdPropuesta   = s.IdPropuesta is > 0 ? s.IdPropuesta : null,
            IdOcReemplaza = s.IdOcReemplaza is > 0 ? s.IdOcReemplaza : null,
            Datos         = DatosOrdenCompra.Normalizar(s.Datos),
            Vinculaciones = DatosOrdenCompra.Vinculaciones(s.Vinculaciones),
            Decision      = DatosOrdenCompra.Decision(s.Decision),
        };
        if (solicitud.Vinculaciones.Count == 0 && solicitud.IdPropuesta is { } idProp && solicitud.Datos.MontoTotal is > 0)
            solicitud.Vinculaciones.Add(new VinculacionOrdenCompraDto { IdPropuesta = idProp, MontoAsignado = solicitud.Datos.MontoTotal.Value });

        var reglas = await repositorio.CompararAsync(solicitud, null, idUsuario, ct);
        if (!conIa || reglas.IdTipoMensaje != 2 || reglas.Datos is null || !ia.Disponible || solicitud.Datos.Conceptos.Count == 0)
            return reglas;

        var (evaluaciones, aviso) = await EvaluacionIaOrdenCompra.EvaluarAsync(repositorio, ia, solicitud.Datos.Conceptos,
            solicitud.Datos.IdMoneda, solicitud.Datos.FacturaIgualOc,
            reglas.Datos.Propuestas.Select(p => new EvaluacionIaOrdenCompra.PropuestaAEvaluar(p.IdPropuesta, p.Numero)).ToList(),
            reglas.Datos.Campos, idUsuario, ct);
        if (evaluaciones is null)
            return aviso is null ? reglas : reglas with { Mensaje = aviso };

        var conIaResultado = await repositorio.CompararAsync(solicitud, evaluaciones, idUsuario, ct);
        return aviso is null || conIaResultado.IdTipoMensaje != 2 ? conIaResultado : conIaResultado with { Mensaje = aviso };
    }
}

/// <summary>
/// Registra la OC con su PDF: valida con reglas, evalúa los conceptos con la IA, valida la decisión del comercial,
/// guarda el PDF y registra la OC con sus vinculaciones (y reemplaza la OC autogenerada si corresponde).
/// Si la decisión es "nueva versión", genera la versión nueva de cada propuesta y la vincula a la OC.
/// </summary>
public class RegistrarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia,
                                           IPropuestasRepositorio propuestas, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = PdfOrdenCompra.TamanoMaximoBytes;

    public async Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> EjecutarAsync(
        long idPropuesta, RegistrarOrdenCompraSolicitudDto s, Stream? pdf, string? nombreArchivo,
        long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0) return new(1, "Propuesta no válida.");
        if (pdf is null) return new(1, "Adjunte el PDF de la orden de compra.");

        var solicitud = new RegistrarOrdenCompraSolicitudDto
        {
            IdOcReemplaza = s.IdOcReemplaza is > 0 ? s.IdOcReemplaza : null,
            Datos         = DatosOrdenCompra.Normalizar(s.Datos),
            Vinculaciones = DatosOrdenCompra.Vinculaciones(s.Vinculaciones),
            Decision      = DatosOrdenCompra.Decision(s.Decision),
        };
        if (solicitud.Decision is null) return new(1, "Indique la decisión: validar, observar, correccion_cliente o nueva_version.");
        if (solicitud.Vinculaciones.Count == 0 && solicitud.Datos.MontoTotal is > 0)
            solicitud.Vinculaciones.Add(new VinculacionOrdenCompraDto { IdPropuesta = idPropuesta, MontoAsignado = solicitud.Datos.MontoTotal.Value });

        using var buffer = new MemoryStream();
        if (await PdfOrdenCompra.LeerAsync(pdf, buffer, ct) is { } errorPdf) return new(1, errorPdf);

        var comparar = new CompararOrdenCompraSolicitudDto
        {
            IdPropuesta = idPropuesta, IdOcReemplaza = solicitud.IdOcReemplaza,
            Datos = solicitud.Datos, Vinculaciones = solicitud.Vinculaciones,
        };

        // 1. Reglas (sin decisión) para dar contexto a la IA
        var reglas = await repositorio.CompararAsync(comparar, null, idUsuario, ct);
        if (reglas.IdTipoMensaje != 2 || reglas.Datos is null) return new(reglas.IdTipoMensaje, reglas.Mensaje);

        // 2. IA por propuesta (si falla, se sigue con las reglas)
        var (evaluaciones, avisoIa) = await EvaluacionIaOrdenCompra.EvaluarAsync(repositorio, ia, solicitud.Datos.Conceptos,
            solicitud.Datos.IdMoneda, solicitud.Datos.FacturaIgualOc,
            reglas.Datos.Propuestas.Select(p => new EvaluacionIaOrdenCompra.PropuestaAEvaluar(p.IdPropuesta, p.Numero)).ToList(),
            reglas.Datos.Campos, idUsuario, ct);

        // 3. Validar la decisión con el resultado final, antes de escribir en disco
        comparar.Decision = solicitud.Decision;
        var decision = await repositorio.CompararAsync(comparar, evaluaciones, idUsuario, ct);
        if (decision.IdTipoMensaje != 2) return new(decision.IdTipoMensaje, decision.Mensaje);

        // 4. Guardar el PDF y registrar (si falla, no dejar el archivo huérfano)
        var archivo = await PdfOrdenCompra.GuardarAsync(almacen, buffer, idPropuesta.ToString(CultureInfo.InvariantCulture),
                                                        nombreArchivo, solicitud.Datos.NumeroOc ?? "", ct);
        var registro = await repositorio.RegistrarAsync(idPropuesta, solicitud, evaluaciones, archivo, idUsuario, ct);
        if (registro.IdTipoMensaje != 2 || registro.Datos is null)
        {
            await almacen.EliminarAsync(archivo.Ruta, CancellationToken.None);
            return registro;
        }

        // 5. "Generar nueva versión de propuesta"
        var nuevas = await EvaluacionIaOrdenCompra.GenerarNuevasVersionesAsync(repositorio, propuestas, registro.Datos, idUsuario, ct);
        return registro with { Datos = registro.Datos with { NuevasVersiones = nuevas, AvisoIa = avisoIa } };
    }
}

/// <summary>
/// Edita la OC (datos, vinculaciones y decisión) con PDF opcional: reemplazo del PDF o la OC corregida por el cliente.
/// Vuelve a validar con reglas e IA.
/// </summary>
public class EditarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia,
                                        IPropuestasRepositorio propuestas, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> EjecutarAsync(
        long idOc, EditarOrdenCompraSolicitudDto s, Stream? pdf, string? nombreArchivo,
        long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");

        var solicitud = new EditarOrdenCompraSolicitudDto
        {
            Datos         = DatosOrdenCompra.Normalizar(s.Datos),
            Vinculaciones = DatosOrdenCompra.Vinculaciones(s.Vinculaciones),
            Decision      = DatosOrdenCompra.Decision(s.Decision),
            TipoPdf       = string.IsNullOrWhiteSpace(s.TipoPdf) ? (pdf is null ? null : "reemplazo") : s.TipoPdf.Trim().ToLowerInvariant(),
            MotivoPdf     = s.MotivoPdf?.Trim(),
        };
        if (solicitud.Decision is null) return new(1, "Indique la decisión: validar, observar, correccion_cliente o nueva_version.");
        if (pdf is not null && solicitud.TipoPdf is not ("reemplazo" or "oc_corregida"))
            return new(1, "Indique si el PDF es un reemplazo o la OC corregida por el cliente.");
        if (pdf is not null && (solicitud.MotivoPdf?.Length ?? 0) < 5)
            return new(1, "Indique el motivo del cambio de PDF (mínimo 5 caracteres).");

        using var buffer = new MemoryStream();
        if (pdf is not null && await PdfOrdenCompra.LeerAsync(pdf, buffer, ct) is { } errorPdf) return new(1, errorPdf);

        var comparar = new CompararOrdenCompraSolicitudDto
        {
            IdOc = idOc, Datos = solicitud.Datos, Vinculaciones = solicitud.Vinculaciones,
        };
        var reglas = await repositorio.CompararAsync(comparar, null, idUsuario, ct);
        if (reglas.IdTipoMensaje != 2 || reglas.Datos is null) return new(reglas.IdTipoMensaje, reglas.Mensaje);

        var (evaluaciones, avisoIa) = await EvaluacionIaOrdenCompra.EvaluarAsync(repositorio, ia, solicitud.Datos.Conceptos,
            solicitud.Datos.IdMoneda, solicitud.Datos.FacturaIgualOc,
            reglas.Datos.Propuestas.Select(p => new EvaluacionIaOrdenCompra.PropuestaAEvaluar(p.IdPropuesta, p.Numero)).ToList(),
            reglas.Datos.Campos, idUsuario, ct);

        comparar.Decision = solicitud.Decision;
        var decision = await repositorio.CompararAsync(comparar, evaluaciones, idUsuario, ct);
        if (decision.IdTipoMensaje != 2) return new(decision.IdTipoMensaje, decision.Mensaje);

        ArchivoPdfOcDto? archivo = null;
        if (pdf is not null)
            archivo = await PdfOrdenCompra.GuardarAsync(almacen, buffer, $"oc-{idOc}", nombreArchivo, solicitud.Datos.NumeroOc ?? "", ct);

        var edicion = await repositorio.EditarAsync(idOc, solicitud, evaluaciones, archivo, idUsuario, ct);
        if (edicion.IdTipoMensaje != 2 || edicion.Datos is null)
        {
            if (archivo is not null) await almacen.EliminarAsync(archivo.Ruta, CancellationToken.None);
            return edicion;
        }

        var nuevas = await EvaluacionIaOrdenCompra.GenerarNuevasVersionesAsync(repositorio, propuestas, edicion.Datos, idUsuario, ct);
        return edicion with { Datos = edicion.Datos with { NuevasVersiones = nuevas, AvisoIa = avisoIa } };
    }
}

/// <summary>
/// Cambia solo el PDF: "reemplazo" (mismo documento, mejor copia) o "oc_corregida" (el cliente corrigió la OC; con los
/// datos corregidos, las vinculaciones que quedan conformes pasan a validadas).
/// </summary>
public class ReemplazarDocumentoOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ResultadoGuardarOrdenCompraDto>> EjecutarAsync(
        long idOc, string? tipo, string? motivo, DatosOrdenCompraDto? datos, Stream? pdf, string? nombreArchivo,
        long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        if (pdf is null) return new(1, "Adjunte el nuevo PDF de la orden de compra.");
        tipo   = string.IsNullOrWhiteSpace(tipo) ? "reemplazo" : tipo.Trim().ToLowerInvariant();
        motivo = motivo?.Trim();

        using var buffer = new MemoryStream();
        if (await PdfOrdenCompra.LeerAsync(pdf, buffer, ct) is { } errorPdf) return new(1, errorPdf);

        // 1. Permiso, estado y motivo antes de escribir en disco
        var previo = await repositorio.ReemplazarDocumentoAsync(idOc, tipo, motivo, null, null, null, idUsuario, ct);
        if (previo.IdTipoMensaje != 2) return previo;

        // 2. Con datos corregidos: reglas + IA contra las propuestas vinculadas
        DatosOrdenCompraDto? normalizados = datos is null ? null : DatosOrdenCompra.Normalizar(datos);
        List<EvaluacionIaPropuestaDto>? evaluaciones = null;
        string? avisoIa = null;
        if (normalizados is not null)
        {
            var detalle = await repositorio.ObtenerDetalleAsync(idOc, idUsuario, ct);
            if (detalle.IdTipoMensaje != 2 || detalle.Datos is null) return new(detalle.IdTipoMensaje, detalle.Mensaje);
            var vinculaciones = detalle.Datos.Propuestas
                .Select(p => new VinculacionOrdenCompraDto { IdPropuesta = p.IdPropuesta, MontoAsignado = p.MontoAsignado }).ToList();

            var reglas = await repositorio.CompararAsync(new CompararOrdenCompraSolicitudDto
            {
                IdOc = idOc, Datos = normalizados, Vinculaciones = vinculaciones,
            }, null, idUsuario, ct);
            if (reglas.IdTipoMensaje != 2 || reglas.Datos is null) return new(reglas.IdTipoMensaje, reglas.Mensaje);

            (evaluaciones, avisoIa) = await EvaluacionIaOrdenCompra.EvaluarAsync(repositorio, ia, normalizados.Conceptos,
                normalizados.IdMoneda, normalizados.FacturaIgualOc,
                reglas.Datos.Propuestas.Select(p => new EvaluacionIaOrdenCompra.PropuestaAEvaluar(p.IdPropuesta, p.Numero)).ToList(),
                reglas.Datos.Campos, idUsuario, ct);
        }

        // 3. Guardar el PDF y registrar el cambio
        var archivo = await PdfOrdenCompra.GuardarAsync(almacen, buffer, $"oc-{idOc}", nombreArchivo,
                                                        normalizados?.NumeroOc ?? idOc.ToString(CultureInfo.InvariantCulture), ct);
        var resultado = await repositorio.ReemplazarDocumentoAsync(idOc, tipo, motivo, normalizados, evaluaciones, archivo, idUsuario, ct);
        if (resultado.IdTipoMensaje != 2 || resultado.Datos is null)
        {
            await almacen.EliminarAsync(archivo.Ruta, CancellationToken.None);
            return resultado;
        }
        return resultado with { Datos = resultado.Datos with { AvisoIa = avisoIa } };
    }
}

/// <summary>Re-validar: vuelve a correr reglas + IA sobre una propuesta vinculada (o todas) con los datos guardados.</summary>
public class RevalidarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAsistenteIaOrdenCompra ia)
{
    public async Task<RespuestaDto<List<RevalidacionOrdenCompraDto>>> EjecutarAsync(long idOc, long? idPropuesta, long idUsuario,
                                                                                    CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        idPropuesta = idPropuesta is > 0 ? idPropuesta : null;

        List<EvaluacionIaPropuestaDto>? evaluaciones = null;
        string? avisoIa = null;
        if (ia.Disponible)
        {
            var detalle = await repositorio.ObtenerDetalleAsync(idOc, idUsuario, ct);
            if (detalle.IdTipoMensaje != 2 || detalle.Datos is null) return new(detalle.IdTipoMensaje, detalle.Mensaje);
            var c = detalle.Datos.Cabecera;
            var aEvaluar = detalle.Datos.Propuestas
                .Where(p => idPropuesta is null || p.IdPropuesta == idPropuesta)
                .Select(p => new EvaluacionIaOrdenCompra.PropuestaAEvaluar(p.IdPropuesta, p.Numero)).ToList();
            (evaluaciones, avisoIa) = await EvaluacionIaOrdenCompra.EvaluarAsync(repositorio, ia, c.Conceptos, c.IdMoneda,
                c.FacturaIgualOc, aEvaluar, detalle.Datos.Diferencias, idUsuario, ct);
        }

        var r = await repositorio.RevalidarAsync(idOc, idPropuesta, evaluaciones, idUsuario, ct);
        return avisoIa is null || r.IdTipoMensaje != 2 ? r : r with { Mensaje = $"{r.Mensaje} {avisoIa}" };
    }
}

// ══════════════════════ OC autogenerada y anulación ══════════════════════

/// <summary>"Generar OC automáticamente" cuando el cliente no emite OC: OC-AUTO con el 100% de la propuesta, sin PDF.</summary>
public class AutogenerarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<OcAutogeneradaDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default) =>
        idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<OcAutogeneradaDto>(1, "Propuesta no válida."))
            : repositorio.AutogenerarAsync(idPropuesta, idUsuario, ct);
}

/// <summary>Modal de anulación: impacto (propuestas, saldos y OS en ejecución) y motivos.</summary>
public class PrepararAnulacionOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionAnulacionOcDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default) =>
        idOc <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionAnulacionOcDto>(1, "Orden de compra no válida."))
            : repositorio.PrepararAnulacionAsync(idOc, idUsuario, ct);
}

/// <summary>Anula la OC: motivo, justificación (mínimo 20 caracteres) y confirmación del impacto si hay OS en ejecución.</summary>
public class AnularOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<AnulacionOrdenCompraDto>> EjecutarAsync(long idOc, AnularOrdenCompraSolicitudDto s, long idUsuario,
                                                                     CancellationToken ct = default)
    {
        if (idOc <= 0)
            return Task.FromResult(new RespuestaDto<AnulacionOrdenCompraDto>(1, "Orden de compra no válida."));
        var solicitud = new AnularOrdenCompraSolicitudDto
        {
            IdMotivo        = s.IdMotivo is > 0 ? s.IdMotivo : null,
            Justificacion   = s.Justificacion?.Trim(),
            ConfirmaImpacto = s.ConfirmaImpacto,
        };
        return repositorio.AnularAsync(idOc, solicitud, idUsuario, ct);
    }
}
