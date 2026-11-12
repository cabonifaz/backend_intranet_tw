using System.Globalization;
using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-27 (rendir gastos) y HU-31 (bandeja del jefe: evidencias forzadas, ensayos con error y gastos) ──────────

/// <summary>
/// Validación de entrada del gasto que rinde el técnico. Desarrollo seguro: listas cerradas, montos mayores a 0 y con 2 decimales como máximo, textos con
/// tope y sin caracteres de control, reparto sin repetidos y con suma exacta, hasta 5 fotos JPEG (validadas por contenido) de máximo 5 MB.
/// El SP vuelve a validar todo y además que las líneas del reparto sean del técnico y de esa OS.
/// </summary>
public static class EntradaGastoMovil
{
    public const int  MaxFotos          = 5;
    public const long MaxBytesFoto      = 5 * 1024 * 1024;
    public const int  MaxLineasReparto  = 12;
    public const decimal ToleranciaIa   = 0.05m;
    public static readonly string[] Origenes = ["viatico", "reembolso"];

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static bool DosDecimales(decimal v) => decimal.Round(v, 2) == v;

    private static bool TextoValido(string? t, int max) => t is null || (t.Length <= max && !t.Any(c => char.IsControl(c) && c is not ('\n' or '\r' or '\t')));

    private static string? Limpio(string? t) => string.IsNullOrWhiteSpace(t) ? null : t.Trim();

    /// <summary>Lee el JSON del campo "datos". Null si no es un JSON válido.</summary>
    public static PeticionGastoMovilDto? Leer(string? datos)
    {
        if (string.IsNullOrWhiteSpace(datos) || datos.Length > 16 * 1024) return null;
        try { return JsonSerializer.Deserialize<PeticionGastoMovilDto>(datos, Json); }
        catch (JsonException) { return null; }
    }

    /// <summary>"[1,3]" o "1,3" → [1, 3]. Null si no se envió; lista vacía con error si tiene algo inválido.</summary>
    public static (List<int>? Lista, bool Valida) LeerConservar(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return (null, true);
        var t = texto.Trim().TrimStart('[').TrimEnd(']');
        var lista = new List<int>();
        foreach (var p in t.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!int.TryParse(p, NumberStyles.None, CultureInfo.InvariantCulture, out var n)) return ([], false);
            lista.Add(n);
        }
        return (lista, true);
    }

    /// <summary>Valida y normaliza. FotosNuevas = cuántas fotos llegan en el multipart. Devuelve el comando (sin rutas ni IA) o el mensaje para el técnico.</summary>
    public static (ComandoGastoMovil? Comando, string? Error) Normalizar(long idGasto, PeticionGastoMovilDto? d, int fotosNuevas)
    {
        var esNuevo = idGasto <= 0;
        if (d is null) return (null, "Datos del gasto incompletos.");

        string? idCliente = null;
        if (esNuevo)
        {
            if (!Guid.TryParse(d.IdCliente, out var g) || g == Guid.Empty) return (null, "Falta el identificador del gasto en el teléfono (idCliente).");
            idCliente = g.ToString("D");
        }

        var origen = (d.Origen ?? "").Trim().ToLowerInvariant();
        if (!Origenes.Contains(origen)) return (null, "El origen del gasto debe ser viatico o reembolso.");
        var idOs = d.IdOs ?? 0;
        if (esNuevo && idOs <= 0) return (null, "Indica el servicio del gasto.");
        if (idOs < 0) return (null, "El servicio indicado no es válido.");

        if (d.Monto is not { } monto || monto <= 0 || monto > 100000m) return (null, "El monto debe ser mayor a 0.");
        if (!DosDecimales(monto)) return (null, "El monto admite hasta 2 decimales.");

        if (!DateOnly.TryParseExact(d.FechaGasto?.Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fecha))
            return (null, "Indica la fecha del gasto (yyyy-MM-dd).");

        var descripcion = Limpio(d.Descripcion);
        var texto = Limpio(d.ConceptoTexto);
        var motivo = Limpio(d.MotivoSinFoto);
        if (!TextoValido(descripcion, 300)) return (null, "La descripción admite hasta 300 caracteres, sin caracteres de control.");
        if (!TextoValido(texto, 100)) return (null, "El concepto admite hasta 100 caracteres, sin caracteres de control.");
        if (!TextoValido(motivo, 300)) return (null, "El motivo admite hasta 300 caracteres, sin caracteres de control.");

        string? repartoJson = null;
        int? idConcepto = null;
        if (origen == "reembolso")
        {
            if (d.IdConcepto is not > 0) return (null, "Elige el concepto del gasto.");
            if (d.Reparto is { Count: > 0 }) return (null, "Un reembolso no lleva reparto entre viáticos.");
            idConcepto = d.IdConcepto;
        }
        else
        {
            var rep = d.Reparto ?? [];
            if (rep.Count == 0) return (null, "Indica de qué viáticos sale el gasto.");
            if (rep.Count > MaxLineasReparto) return (null, $"El reparto admite hasta {MaxLineasReparto} líneas.");
            if (rep.Any(x => x.IdViaticoLinea <= 0 || x.Monto <= 0)) return (null, "Cada línea del reparto debe tener el viático y un monto mayor a 0.");
            if (rep.Any(x => !DosDecimales(x.Monto))) return (null, "Los montos del reparto admiten hasta 2 decimales.");
            if (rep.Select(x => x.IdViaticoLinea).Distinct().Count() != rep.Count) return (null, "Un viático aparece dos veces en el reparto.");
            var suma = rep.Sum(x => x.Monto);
            if (suma != monto) return (null, $"La suma del reparto (S/ {suma:N2}) debe ser igual al monto del gasto (S/ {monto:N2}).");
            repartoJson = JsonSerializer.Serialize(rep.Select(x => new { idViaticoLinea = x.IdViaticoLinea, monto = x.Monto }));
            texto = null;
        }

        string? conservarJson = null;
        List<int> conservar = esNuevo ? new List<int>() : (d.FotosConservar ?? new List<int>());
        if (!esNuevo)
        {
            if (conservar.Any(n => n is < 1 or > MaxFotos) || conservar.Distinct().Count() != conservar.Count)
                return (null, "Las fotos a conservar no son válidas.");
            conservarJson = JsonSerializer.Serialize(conservar);
        }

        if (fotosNuevas + conservar.Count > MaxFotos) return (null, $"Un gasto admite hasta {MaxFotos} fotos.");
        if (fotosNuevas + conservar.Count == 0 && (motivo is null || motivo.Length < 3))
            return (null, "Sin foto del comprobante, indica el motivo (mínimo 3 caracteres).");

        return (new ComandoGastoMovil(Math.Max(idGasto, 0), idCliente, origen, idOs, idConcepto, texto, monto, fecha, descripcion, repartoJson,
            motivo, [], conservarJson, null, null), null);
    }
}

/// <summary>
/// El técnico rinde un gasto (POST, idGasto = 0) o corrige uno observado (PUT, idGasto > 0) en una sola petición multipart: datos (JSON) + hasta 5 fotos.
/// Las fotos se validan por su contenido (JPEG), se guardan con un nombre que genera el servidor y la primera se lee con IA (total de la boleta).
/// Si el SP no registra el gasto, o era un reintento ya registrado, se borran las fotos recién guardadas: no quedan archivos huérfanos.
/// </summary>
public class RendirGastoMovilCasoDeUso(IGastosAprobacionesMovilRepositorio repositorio, ILectorComprobanteIa ia, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ResultadoGastoMovilDto>> EjecutarAsync(
        long idUsuario, long idGasto, string? datos, string? fotosConservar, IReadOnlyList<(Stream Contenido, long Tamano)> fotos, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return new(1, "No se pudo identificar al usuario.");
        if (idGasto < 0) return new(1, "El gasto no existe.");

        var peticion = EntradaGastoMovil.Leer(datos);
        if (peticion is not null && idGasto > 0)
        {
            var (lista, valida) = EntradaGastoMovil.LeerConservar(fotosConservar);
            if (!valida) return new(1, "Las fotos a conservar no son válidas.");
            if (lista is not null) peticion.FotosConservar = lista;
        }
        var (comando, error) = EntradaGastoMovil.Normalizar(idGasto, peticion, fotos.Count);
        if (error is not null) return new(1, error);

        // Fotos: JPEG por contenido y máximo 5 MB cada una
        var imagenes = new List<byte[]>();
        foreach (var (contenido, tamano) in fotos)
        {
            if (tamano <= 0) return new(1, "Una de las fotos está vacía.");
            if (tamano > EntradaGastoMovil.MaxBytesFoto) return new(1, "Cada foto puede pesar hasta 5 MB.");
            using var m = new MemoryStream();
            await contenido.CopyToAsync(m, ct);
            if (m.Length == 0 || m.Length > EntradaGastoMovil.MaxBytesFoto) return new(1, "Cada foto puede pesar hasta 5 MB.");
            var bytes = m.ToArray();
            if (!RegistrarDemoraMovilCasoDeUso.EsJpeg(bytes.AsSpan(0, Math.Min(3, bytes.Length)))) return new(1, "Las fotos deben ser imágenes JPEG tomadas con la cámara.");
            imagenes.Add(bytes);
        }

        var rutas = new List<string>();
        try
        {
            foreach (var img in imagenes)
            {
                var ruta = $"gastos/{idUsuario}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
                await almacen.GuardarAsync(ruta, new MemoryStream(img), ct);
                rutas.Add(ruta);
            }

            // IA: total de la primera foto nueva (si falla o no está configurada, sin lectura)
            decimal? montoIa = null;
            bool? coincide = null;
            if (imagenes.Count > 0)
            {
                try { montoIa = await ia.LeerTotalAsync(imagenes[0], ct); }
                catch (Exception) when (!ct.IsCancellationRequested) { montoIa = null; }
                if (montoIa is { } leido) coincide = Math.Abs(leido - comando!.Monto) <= EntradaGastoMovil.ToleranciaIa;
            }

            var r = await repositorio.RendirGastoAsync(idUsuario, comando! with { FotosNuevas = rutas, MontoIa = montoIa, CoincideIa = coincide }, ct);
            if (r.IdTipoMensaje != 2 || r.Datos is { Duplicado: true })
                await BorrarAsync(rutas);
            return r;
        }
        catch
        {
            await BorrarAsync(rutas);
            throw;
        }
    }

    private async Task BorrarAsync(IEnumerable<string> rutas)
    {
        foreach (var ruta in rutas)
            await almacen.EliminarAsync(ruta, CancellationToken.None);
    }
}

/// <summary>Foto n (1 a 5) de un gasto del propio técnico (JPEG). El técnico sale del token.</summary>
public class ObtenerFotoGastoMovilCasoDeUso(IGastosAprobacionesMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> EjecutarAsync(long idUsuario, long idGasto, int n, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idGasto <= 0 || n is < 1 or > EntradaGastoMovil.MaxFotos) return (null, null, "Foto no encontrada.");
        var r = await repositorio.ObtenerRutaFotoGastoAsync(idUsuario, idGasto, n, ct);
        if (r.IdTipoMensaje != 2 || string.IsNullOrWhiteSpace(r.Datos)) return (null, null, r.Mensaje);
        return await AbrirArchivoAprobacion.AbrirAsync(almacen, r.Datos, ct);
    }
}

/// <summary>Abre una ruta del almacenamiento (sin "..", sin enlaces externos) y deduce el tipo por la extensión.</summary>
internal static class AbrirArchivoAprobacion
{
    internal static async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> AbrirAsync(IAlmacenArchivos almacen, string ruta, CancellationToken ct)
    {
        var r = ruta.Trim();
        if (r.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || r.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || r.Contains(".."))
            return (null, null, "Archivo no encontrado.");
        r = r.TrimStart('/');
        var tipo = Path.GetExtension(r).ToLowerInvariant() switch
        {
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png"            => "image/png",
            ".webp"           => "image/webp",
            ".mp4"            => "video/mp4",
            ".pdf"            => "application/pdf",
            _                 => null
        };
        if (tipo is null) return (null, null, "Archivo no encontrado.");
        var stream = await almacen.AbrirLecturaAsync(r, ct);
        return stream is null ? (null, null, "No se encontró el archivo.") : (stream, tipo, null);
    }
}

/// <summary>Tipos que el jefe resuelve desde la bandeja de la app además de salidas y llegadas.</summary>
public static class EntradaAprobacionJefeMovil
{
    public static readonly string[] Tipos = ["evidencia", "ensayo", "gasto"];
    public const int MaxComentario = 500;

    /// <summary>Evidencia y ensayo: { aprobar, comentario }. Comentario obligatorio al rechazar; hasta 500 caracteres.</summary>
    public static string? ValidarDecision(long id, ResolverAutorizacionSalidaDto? dto)
    {
        if (id <= 0) return "No se encontró la aprobación.";
        if (dto is null) return "Indica si apruebas o rechazas.";
        var c = dto.Comentario?.Trim() ?? "";
        if (!dto.Aprobar && c.Length == 0) return "Indica el motivo del rechazo.";
        if (c.Length > MaxComentario) return $"El comentario admite hasta {MaxComentario} caracteres.";
        if (c.Any(ch => char.IsControl(ch) && ch is not ('\n' or '\r' or '\t'))) return "El comentario tiene caracteres no permitidos.";
        return null;
    }
}

/// <summary>Detalle de una evidencia forzada, un ensayo con error o un gasto para el jefe. A quien no le corresponde se le responde como si no existiera.</summary>
public class ObtenerDetalleAprobacionMovilCasoDeUso(IGastosAprobacionesMovilRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleAprobacionMovilDto>> EjecutarAsync(long idUsuario, string tipo, long id, CancellationToken ct = default)
        => idUsuario <= 0 || id <= 0 || !EntradaAprobacionJefeMovil.Tipos.Contains(tipo)
            ? Task.FromResult(new RespuestaDto<DetalleAprobacionMovilDto>(1, "No se encontró la aprobación o no corresponde a tu área."))
            : repositorio.ObtenerDetalleAsync(idUsuario, tipo, id, ct);
}

/// <summary>Archivo de una evidencia forzada (foto, video o con cuadro = true la miniatura del video) o foto n de un gasto, para el jefe.</summary>
public class ObtenerArchivoAprobacionMovilCasoDeUso(IGastosAprobacionesMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> EjecutarAsync(
        long idUsuario, string tipo, long id, int n, bool cuadro, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || id <= 0 || tipo is not ("evidencia" or "gasto") || (tipo == "gasto" && n is < 1 or > EntradaGastoMovil.MaxFotos))
            return (null, null, "Archivo no encontrado.");
        var r = await repositorio.ObtenerArchivoAsync(idUsuario, tipo, id, tipo == "gasto" ? n : 1, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return (null, null, r.Mensaje);
        var ruta = cuadro && tipo == "evidencia" ? r.Datos.RutaCuadro : r.Datos.Ruta;
        if (string.IsNullOrWhiteSpace(ruta)) return (null, null, "Archivo no encontrado.");
        return await AbrirArchivoAprobacion.AbrirAsync(almacen, ruta, ct);
    }
}

/// <summary>El jefe aprueba o rechaza una evidencia forzada o un ensayo con error. Si otro jefe ya lo resolvió, el SP responde con un mensaje de negocio.</summary>
public class ResolverAprobacionJefeMovilCasoDeUso(IGastosAprobacionesMovilRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(long idUsuario, string tipo, long id, ResolverAutorizacionSalidaDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<bool>(1, "No se pudo identificar al usuario."));
        if (tipo is not ("evidencia" or "ensayo")) return Task.FromResult(new RespuestaDto<bool>(1, "Tipo de aprobación no válido."));
        if (EntradaAprobacionJefeMovil.ValidarDecision(id, dto) is { } e) return Task.FromResult(new RespuestaDto<bool>(1, e));
        var comentario = string.IsNullOrWhiteSpace(dto!.Comentario) ? null : dto.Comentario.Trim();
        return tipo == "evidencia"
            ? repositorio.ResolverEvidenciaAsync(idUsuario, id, dto.Aprobar, comentario, ct)
            : repositorio.ResolverEnsayoAsync(idUsuario, id, dto.Aprobar, comentario, ct);
    }
}

/// <summary>El Jefe de Operaciones aprueba, observa o rechaza un gasto desde la app: { accion, comentario } (obligatorio al observar o rechazar).</summary>
public class RevisarGastoJefeMovilCasoDeUso(IGastosAprobacionesMovilRepositorio repositorio)
{
    public Task<RespuestaDto<RevisarGastoResultadoDto>> EjecutarAsync(long idUsuario, long idGasto, RevisarGastoDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, "No se pudo identificar al usuario."));
        // Mismas reglas que la revisión desde la intranet (HU-45); el primer argumento solo se valida como positivo
        var (accion, comentario, error) = EntradaViaticos.NormalizarRevision(idGasto, idGasto, dto);
        return error is not null
            ? Task.FromResult(new RespuestaDto<RevisarGastoResultadoDto>(1, error == "La programación no existe." ? "El gasto no existe." : error))
            : repositorio.RevisarGastoAsync(idUsuario, idGasto, accion!, comentario, ct);
    }
}
