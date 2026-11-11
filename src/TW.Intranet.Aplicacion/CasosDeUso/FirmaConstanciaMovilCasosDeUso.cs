using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-17 — Firma de informes y constancia de servicio ─────────────────────────────────────────────────

/// <summary>Lista de informes de la OS con sus responsables, el plazo de aceptación tácita y el avance de firmas.</summary>
public class ObtenerFirmasMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<FirmasMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 ? Task.FromResult(new RespuestaDto<FirmasMovilDto>(1, "Servicio no encontrado.")) : repositorio.ObtenerFirmasAsync(idUsuario, idOs, ct);
}

/// <summary>Resumen ligero (para el menú de la orden): cuántos informes hay y cuántos están firmados.</summary>
public class ObtenerResumenFirmasMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ResumenFirmasMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 ? Task.FromResult(new RespuestaDto<ResumenFirmasMovilDto>(1, "Servicio no encontrado.")) : repositorio.ObtenerResumenAsync(idUsuario, idOs, ct);
}

/// <summary>Datos de la constancia de servicio: cliente, contacto, equipos intervenidos, firma del cliente, envío y lo que falta firmar.</summary>
public class ObtenerConstanciaMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ConstanciaMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 ? Task.FromResult(new RespuestaDto<ConstanciaMovilDto>(1, "Servicio no encontrado.")) : repositorio.ObtenerConstanciaAsync(idUsuario, idOs, ct);
}

/// <summary>Utilidades compartidas de la firma (validación de entradas, hash y archivos).</summary>
public static class EntradaFirmaMovil
{
    public const long TamanoMaximoFotoBytes = 6 * 1024 * 1024;
    private static readonly Regex Clave = new("^[0-9a-f]{32}$", RegexOptions.Compiled);

    public static bool ClaveValida(string? clave) => clave is { Length: 32 } && Clave.IsMatch(clave);

    public static string Hash(string texto) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(texto))).ToLowerInvariant();

    /// <summary>Nombre de quien firmó: de 3 a 150 caracteres sin saltos de línea.</summary>
    public static string? Nombre(string? nombre)
    {
        var n = EntradaObjetivosMovil.Limpiar(nombre);
        return n is { Length: >= 3 and <= 150 } && !n.Any(char.IsControl) ? n : null;
    }

    /// <summary>Lee la foto del formato físico (JPEG de la cámara, hasta 6 MB).</summary>
    public static async Task<(byte[]? Bytes, string? Error)> LeerFotoAsync(Stream? s, long tamano, CancellationToken ct)
    {
        if (s is null || tamano <= 0) return (null, "Falta la foto del formato físico.");
        if (tamano > TamanoMaximoFotoBytes) return (null, "La foto no puede superar los 6 MB.");
        using var m = new MemoryStream();
        await s.CopyToAsync(m, ct);
        if (m.Length < 3 || m.Length > TamanoMaximoFotoBytes) return (null, "La foto no es válida.");
        var bytes = m.ToArray();
        return RegistrarDemoraMovilCasoDeUso.EsJpeg(bytes.AsSpan(0, 3)) ? (bytes, null) : (null, "La foto debe ser una imagen JPEG tomada con la cámara.");
    }
}

/// <summary>
/// "Servicio cerrado": cuando TODO está listo (informes completos con sus responsables resueltos, constancia firmada y generada) arma el PDF de la constancia, lo
/// guarda y, solo si el parámetro CONSTANCIA_ENVIO_CORREO = 1, intenta enviarlo al correo del contacto del cliente. Después el SP persiste el cierre. Si algo falla, no
/// se pierde nada: el cierre se reintenta al volver a "Generar constancia" o al firmar. NO cambia el estado de la OS (no hay una regla de cierre iniciada por el técnico).
/// </summary>
public class CierreServicioMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio, IGeneradorConstanciaPdf pdf, IAlmacenArchivos almacen, NotificadorCorreo correo)
{
    public async Task EjecutarAsync(long idUsuario, long idOs, CancellationToken ct)
    {
        string? ruta = null;
        try
        {
            var firmas = await repositorio.ObtenerFirmasAsync(idUsuario, idOs, ct);
            var constancia = await repositorio.ObtenerConstanciaAsync(idUsuario, idOs, ct);
            if (firmas.IdTipoMensaje != 2 || firmas.Datos is null || constancia.IdTipoMensaje != 2 || constancia.Datos is null) return;
            var c = constancia.Datos.Cabecera;
            if (c.CerradaEn is not null || !c.Firmada || c.GeneradaEn is null || !firmas.Datos.Cabecera.Listo) return;

            var bytes = pdf.Generar(new DatosConstanciaPdf(constancia.Datos, firmas.Datos));
            ruta = $"constancias/{idOs}/constancia_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.pdf";
            await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);

            string estado, detalle; string? destino = null;
            if (!c.EnvioActivo) { estado = "desactivado"; detalle = "El envío de la constancia por correo está desactivado (parámetro CONSTANCIA_ENVIO_CORREO)."; }
            else if (string.IsNullOrWhiteSpace(c.ContactoCorreo)) { estado = "sin_correo"; detalle = "El contacto del cliente no tiene correo registrado."; }
            else
            {
                destino = c.ContactoCorreo.Trim();
                var asunto = $"Constancia de servicio {c.NumeroOs}";
                var texto = $"Estimado(a) {c.ContactoNombre ?? "cliente"}:\n\nAdjuntamos la constancia de servicio {c.NumeroOs} firmada.\n\nTotal Weight";
                var html = $"<p>Estimado(a) {System.Net.WebUtility.HtmlEncode(c.ContactoNombre ?? "cliente")}:</p><p>Adjuntamos la constancia de servicio <b>{System.Net.WebUtility.HtmlEncode(c.NumeroOs)}</b> firmada.</p><p>Total Weight</p>";
                var envio = await correo.EnviarAsync("constancia_servicio",
                    new MensajeCorreoDto(destino, c.ContactoNombre, asunto, html, texto, Adjuntos: [new AdjuntoCorreoDto($"constancia-{c.NumeroOs}.pdf", Convert.ToBase64String(bytes))]),
                    "orden_servicio", idOs, idUsuario, ct);
                estado = envio.Enviado ? "enviado" : "error";
                detalle = envio.Enviado ? "Enviado." : (envio.Error ?? "No se pudo enviar el correo.");
            }
            var cierre = await repositorio.RegistrarCierreAsync(idUsuario, idOs, ruta, estado, destino, detalle.Length > 300 ? detalle[..300] : detalle, ct);
            if (cierre.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            if (ruta is not null) await almacen.EliminarAsync(ruta, CancellationToken.None);
        }
    }
}

/// <summary>
/// El técnico registra la firma de UN responsable (por dispositivo, formato físico o "cliente ausente"). Por dispositivo se valida la forma de los trazos, se calcula
/// su hash y se rechaza si es igual (≥ umbral, 90 % por defecto) a la de OTRO responsable de la misma OS. El SP aplica el resto (responsable con informes, servicio abierto).
/// </summary>
public class FirmarResponsableMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio, IAlmacenArchivos almacen, CierreServicioMovilCasoDeUso cierre)
{
    public async Task<RespuestaDto<FirmasMovilDto>> EjecutarAsync(long idUsuario, long idOs, string? clave, PeticionFirmaResponsableMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "Servicio no encontrado.");
        if (!EntradaFirmaMovil.ClaveValida(clave)) return new(1, "El responsable no es válido.");
        var modo = (d?.Modo ?? string.Empty).Trim().ToLowerInvariant();
        if (modo is not ("dispositivo" or "ausente")) return new(1, "La forma de firma no es válida.");

        string? trazos = null, hash = null, motivo = null;
        if (modo == "ausente")
        {
            motivo = EntradaObjetivosMovil.Limpiar(d?.Motivo);
            if (motivo is not { Length: >= 5 and <= 300 }) return new(1, "Indica el motivo por el que el responsable está ausente (de 5 a 300 caracteres).");
        }
        else
        {
            trazos = d?.Trazos is { } t ? t.GetRawText() : null;
            var (leidos, error) = ComparadorFirmas.Leer(trazos);
            if (leidos is null) return new(1, error ?? "La firma no es válida.");
            var comparables = await repositorio.ObtenerComparablesAsync(idUsuario, idOs, clave!, ct);
            if (comparables.IdTipoMensaje != 2 || comparables.Datos is null) return new(comparables.IdTipoMensaje, comparables.Mensaje);
            if (ComparadorFirmas.MasParecida(trazos!, comparables.Datos.Firmas.Select(f => (f.Nombre, f.Trazos))) is { } parecida && parecida.Pct >= comparables.Datos.UmbralPct)
                return new(1, ComparadorFirmas.MensajeRechazo(parecida.Nombre, parecida.Pct));
            hash = EntradaFirmaMovil.Hash(trazos!);
        }

        var r = await repositorio.GuardarFirmaAsync(idUsuario, idOs, clave!, modo, trazos, hash, null, null, motivo, ct);
        return await TerminarAsync(idUsuario, idOs, r, ct);
    }

    public async Task<RespuestaDto<FirmasMovilDto>> EjecutarFisicoAsync(long idUsuario, long idOs, string? clave, Stream? foto, long tamano, string? nombre, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "Servicio no encontrado.");
        if (!EntradaFirmaMovil.ClaveValida(clave)) return new(1, "El responsable no es válido.");
        var quien = EntradaFirmaMovil.Nombre(nombre);
        if (quien is null) return new(1, "Indica el nombre de quien firmó (de 3 a 150 caracteres).");
        var (bytes, error) = await EntradaFirmaMovil.LeerFotoAsync(foto, tamano, ct);
        if (bytes is null) return new(1, error ?? "La foto no es válida.");

        var ruta = $"firmas/{idOs}/{clave}_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
        await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);
        RespuestaDto<RegistroFirmaMovilDto> r;
        try { r = await repositorio.GuardarFirmaAsync(idUsuario, idOs, clave!, "fisico", null, null, quien, ruta, null, ct); }
        catch { await almacen.EliminarAsync(ruta, CancellationToken.None); throw; }
        if (r.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
        return await TerminarAsync(idUsuario, idOs, r, ct);
    }

    private async Task<RespuestaDto<FirmasMovilDto>> TerminarAsync(long idUsuario, long idOs, RespuestaDto<RegistroFirmaMovilDto> r, CancellationToken ct)
    {
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        if (r.Datos.RutaFotoAnterior is { Length: > 0 } anterior) await almacen.EliminarAsync(anterior, CancellationToken.None);
        if (r.Datos.CierreListo) await cierre.EjecutarAsync(idUsuario, idOs, ct);
        var lista = await repositorio.ObtenerFirmasAsync(idUsuario, idOs, ct);
        return lista.IdTipoMensaje == 2 ? new(2, r.Mensaje, lista.Datos) : new(lista.IdTipoMensaje, lista.Mensaje);
    }
}

/// <summary>Firma del cliente en la constancia (dispositivo o formato físico) y "Generar constancia". Devuelve la constancia actualizada.</summary>
public class FirmarConstanciaMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio, IAlmacenArchivos almacen, CierreServicioMovilCasoDeUso cierre)
{
    public async Task<RespuestaDto<ConstanciaMovilDto>> FirmaAsync(long idUsuario, long idOs, PeticionFirmaConstanciaMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "Servicio no encontrado.");
        var nombre = EntradaFirmaMovil.Nombre(d?.Nombre);
        if (nombre is null) return new(1, "Indica el nombre de quien firma (de 3 a 150 caracteres).");
        var trazos = d?.Trazos is { } t ? t.GetRawText() : null;
        var (leidos, error) = ComparadorFirmas.Leer(trazos);
        if (leidos is null) return new(1, error ?? "La firma no es válida.");
        var r = await repositorio.GuardarConstanciaAsync(idUsuario, idOs, "firma", trazos, EntradaFirmaMovil.Hash(trazos!), nombre, null, ct);
        return await TerminarAsync(idUsuario, idOs, r, ct);
    }

    public async Task<RespuestaDto<ConstanciaMovilDto>> FisicoAsync(long idUsuario, long idOs, Stream? foto, long tamano, string? nombre, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "Servicio no encontrado.");
        var quien = EntradaFirmaMovil.Nombre(nombre);
        if (quien is null) return new(1, "Indica el nombre de quien firmó (de 3 a 150 caracteres).");
        var (bytes, error) = await EntradaFirmaMovil.LeerFotoAsync(foto, tamano, ct);
        if (bytes is null) return new(1, error ?? "La foto no es válida.");
        var ruta = $"constancias/{idOs}/formato_fisico_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
        await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);
        RespuestaDto<RegistroConstanciaMovilDto> r;
        try { r = await repositorio.GuardarConstanciaAsync(idUsuario, idOs, "fisico", null, null, quien, ruta, ct); }
        catch { await almacen.EliminarAsync(ruta, CancellationToken.None); throw; }
        if (r.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
        return await TerminarAsync(idUsuario, idOs, r, ct);
    }

    public async Task<RespuestaDto<ConstanciaMovilDto>> GenerarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "Servicio no encontrado.");
        var r = await repositorio.GuardarConstanciaAsync(idUsuario, idOs, "generar", null, null, null, null, ct);
        return await TerminarAsync(idUsuario, idOs, r, ct);
    }

    private async Task<RespuestaDto<ConstanciaMovilDto>> TerminarAsync(long idUsuario, long idOs, RespuestaDto<RegistroConstanciaMovilDto> r, CancellationToken ct)
    {
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);
        if (r.Datos.RutaFotoAnterior is { Length: > 0 } anterior) await almacen.EliminarAsync(anterior, CancellationToken.None);
        if (r.Datos.CierreListo) await cierre.EjecutarAsync(idUsuario, idOs, ct);
        var c = await repositorio.ObtenerConstanciaAsync(idUsuario, idOs, ct);
        return c.IdTipoMensaje == 2 ? new(2, r.Mensaje, c.Datos) : new(c.IdTipoMensaje, c.Mensaje);
    }
}

/// <summary>PDF de la constancia ya generada (o, con tipo foto, la foto del formato físico). Solo de una OS del técnico.</summary>
public class ObtenerArchivoConstanciaMovilCasoDeUso(IFirmaConstanciaMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> EjecutarAsync(long idUsuario, long idOs, string? tipo, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return (null, null, "Servicio no encontrado.");
        var t = (tipo ?? "pdf").Trim().ToLowerInvariant();
        if (t is not ("pdf" or "foto")) return (null, null, "El archivo pedido no es válido.");
        var r = await repositorio.ObtenerRutaArchivoAsync(idUsuario, idOs, t, ct);
        if (r.IdTipoMensaje != 2 || string.IsNullOrEmpty(r.Datos)) return (null, null, r.Mensaje);
        var s = await almacen.AbrirLecturaAsync(r.Datos, ct);
        return s is null ? (null, null, "El archivo ya no está disponible.") : (s, t == "pdf" ? "application/pdf" : "image/jpeg", null);
    }
}
