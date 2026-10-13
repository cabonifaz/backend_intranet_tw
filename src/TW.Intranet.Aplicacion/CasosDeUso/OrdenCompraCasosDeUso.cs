using System.Security.Cryptography;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ══════════════════════ HU-22 — Registro de Orden de Compra recibida ══════════════════════

/// <summary>Validaciones de forma comunes (el SP vuelve a validar todo contra la BD).</summary>
internal static class ValidacionOrdenCompra
{
    public static string? Validar(DatosOrdenCompraDto d)
    {
        var numero = d.NumeroOc?.Trim() ?? "";
        if (numero.Length == 0)                     return "Ingrese el número de la orden de compra.";
        if (numero.Length > 50)                     return "El número de la orden de compra admite hasta 50 caracteres.";
        if (d.FechaOc is null)                      return "Indique la fecha de la orden de compra.";
        if (d.FechaRecepcion is null)               return "Indique la fecha de recepción.";
        if (d.IdMoneda is null or <= 0)             return "Seleccione la moneda de la orden de compra.";
        if (d.Monto is null or <= 0)                return "Ingrese el monto de la orden de compra (mayor a 0).";
        if (d.Monto > 999_999_999_999m)             return "El monto de la orden de compra es demasiado grande.";
        if (d.VigenciaDias is null or < 1 or > 3650) return "Indique la vigencia de la orden de compra en días (1 a 3650).";
        if ((d.Observaciones?.Trim().Length ?? 0) > 500) return "Las observaciones admiten hasta 500 caracteres.";
        if ((d.Referencia?.Trim().Length ?? 0) > 200)    return "La referencia admite hasta 200 caracteres.";
        return null;
    }

    public static DatosOrdenCompraDto Normalizar(DatosOrdenCompraDto d) => d with
    {
        NumeroOc       = d.NumeroOc?.Trim(),
        FechaOc        = d.FechaOc?.Date,
        FechaRecepcion = d.FechaRecepcion?.Date,
        Monto          = d.Monto is { } m ? Math.Round(m, 2) : null,
        Observaciones  = string.IsNullOrWhiteSpace(d.Observaciones) ? null : d.Observaciones.Trim(),
        Referencia     = string.IsNullOrWhiteSpace(d.Referencia) ? null : d.Referencia.Trim(),
    };
}

/// <summary>Lectura y verificación del PDF de la OC (registro HU-22 y edición HU-24).</summary>
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
        $"ordenes-compra/{carpeta}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.pdf";

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
}

/// <summary>Datos del modal: propuesta aceptada (monto y moneda para la cobertura), monedas y vigencia sugerida.</summary>
public class PrepararOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionOrdenCompraDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<PreparacionOrdenCompraDto>(1, "Propuesta no válida."));
        return repositorio.PrepararAsync(idPropuesta, idUsuario, ct);
    }
}

/// <summary>Indicador de cobertura en vivo: compara el monto de la OC con el de la propuesta, sin guardar.</summary>
public class CalcularCoberturaOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<CoberturaOrdenCompraDto>> EjecutarAsync(
        long idPropuesta, DatosOrdenCompraDto datos, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<CoberturaOrdenCompraDto>(1, "Propuesta no válida."));
        if (ValidacionOrdenCompra.Validar(datos) is { } error)
            return Task.FromResult(new RespuestaDto<CoberturaOrdenCompraDto>(1, error));
        return repositorio.ValidarAsync(idPropuesta, ValidacionOrdenCompra.Normalizar(datos), idUsuario, ct);
    }
}

/// <summary>
/// Registra la OC con su PDF obligatorio: valida en BD, guarda el PDF (máx. 10 MB, firma %PDF-),
/// registra la OC en 'pendiente_validacion' vinculada a la propuesta y notifica a Contabilidad y Operaciones.
/// </summary>
public class RegistrarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = PdfOrdenCompra.TamanoMaximoBytes;

    public async Task<RespuestaDto<OrdenCompraRegistradaDto>> EjecutarAsync(
        long idPropuesta, DatosOrdenCompraDto datos, Stream? pdf, string? nombreArchivo, long tamanoBytes,
        long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0) return new(1, "Propuesta no válida.");
        if (ValidacionOrdenCompra.Validar(datos) is { } error) return new(1, error);
        if (pdf is null || tamanoBytes <= 0) return new(1, "Adjunte el PDF de la orden de compra.");
        if (tamanoBytes > TamanoMaximoBytes) return new(1, "El PDF de la orden de compra no puede superar los 10 MB.");

        var normalizados = ValidacionOrdenCompra.Normalizar(datos);

        // 1. Validar en BD antes de escribir nada en disco
        var validacion = await repositorio.ValidarAsync(idPropuesta, normalizados, idUsuario, ct);
        if (validacion.IdTipoMensaje != 2) return new(validacion.IdTipoMensaje, validacion.Mensaje);

        // 2. Leer y verificar el PDF
        using var buffer = new MemoryStream();
        var errorPdf = await PdfOrdenCompra.LeerAsync(pdf, buffer, ct);
        if (errorPdf is not null) return new(1, errorPdf);
        var hash   = PdfOrdenCompra.Hash(buffer);
        var nombre = PdfOrdenCompra.NormalizarNombre(nombreArchivo, normalizados.NumeroOc!);
        var ruta   = PdfOrdenCompra.Ruta(idPropuesta.ToString());

        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);

        // 3. Registrar (si falla, no dejar el archivo huérfano)
        var registro = await repositorio.RegistrarAsync(idPropuesta,
            new ComandoOrdenCompra(normalizados, ruta, nombre, buffer.Length, hash), idUsuario, ct);
        if (registro.IdTipoMensaje != 2)
            await almacen.EliminarAsync(ruta, CancellationToken.None);

        return registro;
    }
}

/// <summary>Abre el PDF de una orden de compra para verlo o descargarlo.</summary>
public class ObtenerPdfOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        var ruta = await repositorio.ObtenerRutaPdfAsync(idOc, idUsuario, ct);
        if (ruta.IdTipoMensaje != 2 || ruta.Datos is null) return new(ruta.IdTipoMensaje, ruta.Mensaje);

        var contenido = await almacen.AbrirLecturaAsync(ruta.Datos.Ruta, ct);
        if (contenido is null)
            return new(1, "El PDF de la orden de compra está registrado pero no se encontró en el almacenamiento.");

        return new(2, ruta.Mensaje, new ArchivoDescargaDto(contenido, ruta.Datos.NombreArchivo, "application/pdf"));
    }
}

// ══════════════════════ HU-23 — Bandeja y Detalle de Órdenes de Compra ══════════════════════

/// <summary>Bandeja: tarjetas de estado, filas con monto OC, aplicado, saldo, cobertura y estado, y opciones de filtro.</summary>
public class ObtenerBandejaOrdenesCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    private static readonly string[] Estados =
    [
        "", "activas", "vigentes", "pendiente_validacion", "validada", "validada_parcial", "observada",
        "bloqueada", "listas_programacion", "vencida", "anulada", "todas",
    ];

    private static readonly string[] Coberturas = ["", "completa", "con_saldo", "insuficiente", "moneda_diferente", "pendiente"];

    public Task<RespuestaDto<BandejaOrdenesCompraDto>> EjecutarAsync(
        FiltrosBandejaOrdenesCompraDto f, long idUsuario, CancellationToken ct = default)
    {
        var estado    = f.Estado?.Trim().ToLowerInvariant() ?? "";
        var cobertura = f.Cobertura?.Trim().ToLowerInvariant() ?? "";

        if (!Estados.Contains(estado))
            return Task.FromResult(new RespuestaDto<BandejaOrdenesCompraDto>(1,
                "Estado no válido. Use activas, vigentes, pendiente_validacion, validada, validada_parcial, " +
                "observada, bloqueada, listas_programacion, vencida, anulada o todas."));
        if (!Coberturas.Contains(cobertura))
            return Task.FromResult(new RespuestaDto<BandejaOrdenesCompraDto>(1,
                "Cobertura no válida. Use completa, con_saldo, insuficiente, moneda_diferente o pendiente."));
        if (f.FechaDesde is { } desde && f.FechaHasta is { } hasta && desde.Date > hasta.Date)
            return Task.FromResult(new RespuestaDto<BandejaOrdenesCompraDto>(1,
                "La fecha desde no puede ser posterior a la fecha hasta."));

        var filtros = f with
        {
            Estado        = estado,
            Cobertura     = cobertura,
            IdCliente     = f.IdCliente     is > 0 ? f.IdCliente     : null,
            IdResponsable = f.IdResponsable is > 0 ? f.IdResponsable : null,
            FechaDesde    = f.FechaDesde?.Date,
            FechaHasta    = f.FechaHasta?.Date,
            Busqueda      = string.IsNullOrWhiteSpace(f.Busqueda) ? null : f.Busqueda.Trim(),
            Pagina        = Math.Max(1, f.Pagina),
            PorPagina     = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina,
        };
        return repositorio.ObtenerBandejaAsync(filtros, idUsuario, ct);
    }
}

/// <summary>Detalle: datos generales, cobertura económica, aplicaciones, checklist, vinculaciones, documentos, workflow e historial.</summary>
public class ObtenerDetalleOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleOrdenCompraDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0)
            return Task.FromResult(new RespuestaDto<DetalleOrdenCompraDto>(1, "Orden de compra no válida."));
        return repositorio.ObtenerDetalleAsync(idOc, idUsuario, ct);
    }
}

/// <summary>Propuestas aceptadas sin OC para el botón "+ Nueva Orden de Compra" (luego se usa el registro de la HU-22).</summary>
public class ObtenerPropuestasSinOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<List<PropuestaSinOrdenCompraDto>>> EjecutarAsync(string? busqueda, long idUsuario, CancellationToken ct = default)
    {
        var texto = string.IsNullOrWhiteSpace(busqueda) ? null : busqueda.Trim();
        if (texto is { Length: > 200 }) texto = texto[..200];
        return repositorio.ObtenerPropuestasSinOrdenCompraAsync(texto, idUsuario, ct);
    }
}

// ══════════════════════ HU-24 — Registro y Edición de Orden de Compra ══════════════════════

/// <summary>Panel lateral en tiempo real (cobertura + checklist de negocio) para el registro y la edición.</summary>
public class EvaluarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    private static EvaluacionOrdenCompraSolicitudDto Normalizar(EvaluacionOrdenCompraSolicitudDto d) => d with
    {
        NumeroOc = string.IsNullOrWhiteSpace(d.NumeroOc) ? null : d.NumeroOc.Trim()[..Math.Min(d.NumeroOc.Trim().Length, 50)],
        IdMoneda = d.IdMoneda is > 0 ? d.IdMoneda : null,
        Monto    = d.Monto is > 0 and <= 999_999_999_999m ? Math.Round(d.Monto.Value, 2) : null,
    };

    public Task<RespuestaDto<EvaluacionOrdenCompraDto>> EvaluarRegistroAsync(
        long idPropuesta, EvaluacionOrdenCompraSolicitudDto datos, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<EvaluacionOrdenCompraDto>(1, "Propuesta no válida."));
        return repositorio.EvaluarAsync(idPropuesta, null, Normalizar(datos), idUsuario, ct);
    }

    public Task<RespuestaDto<EvaluacionOrdenCompraDto>> EvaluarEdicionAsync(
        long idOc, EvaluacionOrdenCompraSolicitudDto datos, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0)
            return Task.FromResult(new RespuestaDto<EvaluacionOrdenCompraDto>(1, "Orden de compra no válida."));
        return repositorio.EvaluarAsync(null, idOc, Normalizar(datos), idUsuario, ct);
    }
}

/// <summary>Datos de la pantalla "Editar Orden de Compra".</summary>
public class PrepararEdicionOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio)
{
    public Task<RespuestaDto<EdicionOrdenCompraDto>> EjecutarAsync(long idOc, long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0)
            return Task.FromResult(new RespuestaDto<EdicionOrdenCompraDto>(1, "Orden de compra no válida."));
        return repositorio.PrepararEdicionAsync(idOc, idUsuario, ct);
    }
}

/// <summary>
/// Edita la OC: valida en BD, guarda el PDF nuevo si llega (opcional) y actualiza. Cambiar monto o moneda
/// de una OC validada, o "Guardar y revalidar", la regresa a validación y notifica a Contabilidad y Operaciones.
/// </summary>
public class EditarOrdenCompraCasoDeUso(IOrdenCompraRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<OrdenCompraEditadaDto>> EjecutarAsync(
        long idOc, EditarOrdenCompraSolicitudDto datos, Stream? pdf, string? nombreArchivo, long tamanoBytes,
        long idUsuario, CancellationToken ct = default)
    {
        if (idOc <= 0) return new(1, "Orden de compra no válida.");
        if (ValidacionOrdenCompra.Validar(datos) is { } error) return new(1, error);
        if (pdf is not null && tamanoBytes > PdfOrdenCompra.TamanoMaximoBytes)
            return new(1, "El PDF de la orden de compra no puede superar los 10 MB.");

        var normalizados = ValidacionOrdenCompra.Normalizar(datos);

        // 1. Validar en BD antes de escribir nada en disco
        var validacion = await repositorio.EditarAsync(idOc,
            new ComandoEdicionOrdenCompra(normalizados, datos.Revalidar, null, null, null, null),
            soloValidar: true, idUsuario, ct);
        if (validacion.IdTipoMensaje != 2) return validacion;

        // 2. Sin PDF nuevo: se guardan solo los datos
        if (pdf is null || tamanoBytes <= 0)
            return await repositorio.EditarAsync(idOc,
                new ComandoEdicionOrdenCompra(normalizados, datos.Revalidar, null, null, null, null),
                soloValidar: false, idUsuario, ct);

        // 3. Con PDF nuevo: verificar, guardar y registrar (el anterior se conserva para el historial)
        using var buffer = new MemoryStream();
        var errorPdf = await PdfOrdenCompra.LeerAsync(pdf, buffer, ct);
        if (errorPdf is not null) return new(1, errorPdf);

        var ruta = PdfOrdenCompra.Ruta($"oc-{idOc}");
        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);

        var resultado = await repositorio.EditarAsync(idOc,
            new ComandoEdicionOrdenCompra(normalizados, datos.Revalidar, ruta,
                PdfOrdenCompra.NormalizarNombre(nombreArchivo, normalizados.NumeroOc!), buffer.Length, PdfOrdenCompra.Hash(buffer)),
            soloValidar: false, idUsuario, ct);
        if (resultado.IdTipoMensaje != 2)
            await almacen.EliminarAsync(ruta, CancellationToken.None);

        return resultado;
    }
}
