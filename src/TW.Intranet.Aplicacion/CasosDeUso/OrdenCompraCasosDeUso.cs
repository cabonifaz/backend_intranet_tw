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
        return null;
    }

    public static DatosOrdenCompraDto Normalizar(DatosOrdenCompraDto d) => d with
    {
        NumeroOc       = d.NumeroOc?.Trim(),
        FechaOc        = d.FechaOc?.Date,
        FechaRecepcion = d.FechaRecepcion?.Date,
        Monto          = d.Monto is { } m ? Math.Round(m, 2) : null,
        Observaciones  = string.IsNullOrWhiteSpace(d.Observaciones) ? null : d.Observaciones.Trim(),
    };
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
    public const long TamanoMaximoBytes = 10 * 1024 * 1024;

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
        await pdf.CopyToAsync(buffer, ct);
        if (buffer.Length == 0)                 return new(1, "Adjunte el PDF de la orden de compra.");
        if (buffer.Length > TamanoMaximoBytes)  return new(1, "El PDF de la orden de compra no puede superar los 10 MB.");

        var (esPdf, hash) = Analizar(buffer);
        if (!esPdf)                             return new(1, "El archivo de la orden de compra no es un PDF válido.");

        var nombre = NormalizarNombre(nombreArchivo, normalizados.NumeroOc!);
        var ruta   = $"ordenes-compra/{idPropuesta}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.pdf";

        buffer.Position = 0;
        await almacen.GuardarAsync(ruta, buffer, ct);

        // 3. Registrar (si falla, no dejar el archivo huérfano)
        var registro = await repositorio.RegistrarAsync(idPropuesta,
            new ComandoOrdenCompra(normalizados, ruta, nombre, buffer.Length, hash), idUsuario, ct);
        if (registro.IdTipoMensaje != 2)
            await almacen.EliminarAsync(ruta, CancellationToken.None);

        return registro;
    }

    /// <summary>Verifica la firma "%PDF-" (no basta con la extensión) y calcula el SHA-256.</summary>
    private static (bool EsPdf, string Hash) Analizar(MemoryStream buffer)
    {
        ReadOnlySpan<byte> bytes = buffer.GetBuffer().AsSpan(0, (int)buffer.Length);
        bool esPdf = bytes.StartsWith("%PDF-"u8);
        return (esPdf, esPdf ? Convert.ToHexStringLower(SHA256.HashData(bytes)) : "");
    }

    private static string NormalizarNombre(string? nombreArchivo, string numeroOc)
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
