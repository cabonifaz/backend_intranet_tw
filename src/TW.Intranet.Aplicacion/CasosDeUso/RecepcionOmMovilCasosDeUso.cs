using System.Text.Json;
using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-23 — Recepción de instrumentos (OM) en el taller ─────────────────────────────────────────────

/// <summary>
/// Catálogos fijos de la recepción (los mismos del SP de apoyo SP_CatalogoAccesoriosRecepcionOmMovil y de la app): accesorios recibidos, medios de entrega y estados físicos.
/// Etiquetas para el PDF de la constancia.
/// </summary>
public static class CatalogoRecepcionOm
{
    public static readonly IReadOnlyList<(string Codigo, string Etiqueta)> Accesorios =
    [
        ("caja_original", "Caja original"),
        ("adaptador_corriente", "Adaptador de corriente"),
        ("protector_plato", "Protector de plato"),
        ("manual", "Manual"),
        ("otro", "Otro"),
    ];

    public static readonly IReadOnlyList<(string Codigo, string Etiqueta)> Medios =
    [
        ("cliente_taller", "Cliente en taller"),
        ("courier", "Courier"),
        ("traslado_tw", "Traslado TW"),
    ];

    public static readonly IReadOnlySet<string> EstadosFisicos = new HashSet<string> { "conforme", "observado" };

    public static string EtiquetaAccesorio(string codigo) => Accesorios.FirstOrDefault(a => a.Codigo == codigo).Etiqueta ?? codigo;
    public static string EtiquetaMedio(string? codigo) => Medios.FirstOrDefault(m => m.Codigo == codigo).Etiqueta ?? (codigo ?? "—");

    public static string EtiquetaEstado(string? estado) => estado switch
    {
        "conforme" => "Conforme", "observado" => "Observado", "parcial" => "Parcial", _ => estado ?? "—",
    };
}

/// <summary>Lo que el caso de uso ya validó y normalizó para el SP.</summary>
public record ComandoRecepcionOm(
    string NumeroGuia, string MedioEntrega, string EntregoNombre, string? EntregoCargo, string? MotivoParcial, string InstrumentosJson, string FirmaJson);

/// <summary>Validación de la entrada de la recepción (la regla del estado parcial / observado / conforme la decide el SP, que vuelve a validar todo).</summary>
public static class EntradaRecepcionOmMovil
{
    public const int MinGuia = 3, MaxGuia = 40;
    public const int MinEntrego = 3, MaxEntrego = 120, MaxCargo = 120;
    public const int MaxMotivo = 300;
    public const int MinObservaciones = 10, MaxObservaciones = 500;
    public const int MinFotos = 3, MaxFotos = 8;
    public const int MaxInstrumentos = 50;
    public const int MaxBusqueda = 80;
    public const long TamanoMaximoFotoBytes = 6 * 1024 * 1024;

    /// <summary>Texto de una línea: los saltos de línea y tabulaciones pasan a espacio, sin caracteres de control, espacios juntos y recortado; vacío = null.</summary>
    public static string? Texto(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var t = EntradaObjetivosMovil.Limpiar(Regex.Replace(texto, @"[\r\n\t\v\f]+", " "));
        return t is null ? null : Regex.Replace(t, @" {2,}", " ");
    }

    /// <summary>Búsqueda de la lista: hasta 80 caracteres; devuelve el mensaje de error o null.</summary>
    public static string? ValidarBusqueda(string? texto, out string? limpia)
    {
        limpia = Texto(texto);
        return limpia is { Length: > MaxBusqueda } ? $"La búsqueda puede tener hasta {MaxBusqueda} caracteres." : null;
    }

    public static (ComandoRecepcionOm? Comando, string? Error) Validar(PeticionRecepcionOmMovilDto? d)
    {
        if (d is null) return (null, "Datos incompletos.");

        var guia = Texto(d.NumeroGuia);
        if (guia is not { Length: >= MinGuia and <= MaxGuia }) return (null, $"Escribe el N° de guía de remisión (de {MinGuia} a {MaxGuia} caracteres).");
        var medio = (d.MedioEntrega ?? string.Empty).Trim().ToLowerInvariant();
        if (!CatalogoRecepcionOm.Medios.Any(m => m.Codigo == medio)) return (null, "Elige el medio de entrega: Cliente en taller, Courier o Traslado TW.");
        var entrego = Texto(d.EntregoNombre);
        if (entrego is not { Length: >= MinEntrego and <= MaxEntrego }) return (null, $"Escribe el nombre de quien entrega (de {MinEntrego} a {MaxEntrego} caracteres).");
        var cargo = Texto(d.EntregoCargo);
        if (cargo is { Length: > MaxCargo }) return (null, $"La empresa o cargo de quien entrega puede tener hasta {MaxCargo} caracteres.");
        var motivo = Texto(d.MotivoParcial);
        if (motivo is { Length: > MaxMotivo }) return (null, $"El motivo de la recepción parcial puede tener hasta {MaxMotivo} caracteres.");

        if (d.Instrumentos is not { Count: >= 1 }) return (null, "Marca al menos un instrumento recibido.");
        if (d.Instrumentos.Count > MaxInstrumentos) return (null, $"Una recepción admite hasta {MaxInstrumentos} instrumentos.");
        var vistos = new HashSet<long>();
        var lista = new List<object>();
        foreach (var i in d.Instrumentos)
        {
            if (i is null || i.IdOsEquipo <= 0 || !vistos.Add(i.IdOsEquipo)) return (null, "Los instrumentos de la recepción no son válidos o están repetidos.");
            var estado = (i.EstadoFisico ?? string.Empty).Trim().ToLowerInvariant();
            if (!CatalogoRecepcionOm.EstadosFisicos.Contains(estado)) return (null, "Elige el estado físico (Conforme u Observado) de cada instrumento.");
            var obs = Texto(i.Observaciones);
            if (obs is not { Length: >= MinObservaciones and <= MaxObservaciones })
                return (null, $"Escribe las observaciones de cada instrumento (de {MinObservaciones} a {MaxObservaciones} caracteres).");

            var accesorios = new List<string>();
            foreach (var a in i.Accesorios ?? [])
            {
                var codigo = (a ?? string.Empty).Trim().ToLowerInvariant();
                if (!CatalogoRecepcionOm.Accesorios.Any(x => x.Codigo == codigo)) return (null, "Hay un accesorio que no existe en la lista (Caja original, Adaptador de corriente, Protector de plato, Manual u Otro).");
                if (!accesorios.Contains(codigo)) accesorios.Add(codigo);
            }

            var fotos = i.Fotos ?? [];
            if (fotos.Count is < MinFotos or > MaxFotos || fotos.Any(f => f <= 0) || fotos.Distinct().Count() != fotos.Count)
                return (null, $"Cada instrumento necesita de {MinFotos} a {MaxFotos} fotos de recepción (solo cámara).");

            lista.Add(new { idOsEquipo = i.IdOsEquipo, estadoFisico = estado, observaciones = obs, accesorios, fotos });
        }

        // La firma de quien entrega: el mismo formato y la misma validación que la firma de la HU-17 (trazos normalizados de 0 a 1)
        if (d.Firma is not { ValueKind: JsonValueKind.Object } firma) return (null, "Falta la firma de quien entrega.");
        var firmaJson = firma.GetRawText();
        var (trazos, errorFirma) = ComparadorFirmas.Leer(firmaJson);
        if (trazos is null) return (null, errorFirma ?? "La firma no es válida. Vuelve a dibujarla.");

        return (new ComandoRecepcionOm(guia, medio, entrego, cargo, motivo, JsonSerializer.Serialize(lista), firmaJson), null);
    }

    /// <summary>Lee la foto de un instrumento (JPEG de la cámara, hasta 6 MB, validada por la firma de los bytes).</summary>
    public static async Task<(byte[]? Bytes, string? Error)> LeerFotoAsync(Stream? s, long tamano, CancellationToken ct)
    {
        if (s is null || tamano <= 0) return (null, "Falta la foto.");
        if (tamano > TamanoMaximoFotoBytes) return (null, "La foto no puede superar los 6 MB.");
        using var m = new MemoryStream();
        await s.CopyToAsync(m, ct);
        if (m.Length < 3 || m.Length > TamanoMaximoFotoBytes) return (null, "La foto no es válida.");
        var bytes = m.ToArray();
        return RegistrarDemoraMovilCasoDeUso.EsJpeg(bytes.AsSpan(0, 3)) ? (bytes, null) : (null, "La foto debe ser una imagen JPEG tomada con la cámara.");
    }
}

/// <summary>Lista «Por recibir» y «Recibidos hoy» de las OM del técnico de Metrología, con búsqueda por N° de OM, cliente o N° de guía.</summary>
public class ObtenerListaRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ListaRecepcionOmMovilDto>> EjecutarAsync(long idUsuario, string? busqueda, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<ListaRecepcionOmMovilDto>(1, "Usuario no válido."));
        if (EntradaRecepcionOmMovil.ValidarBusqueda(busqueda, out var limpia) is { } error) return Task.FromResult(new RespuestaDto<ListaRecepcionOmMovilDto>(1, error));
        return repositorio.ObtenerListaAsync(idUsuario, limpia, ct);
    }
}

/// <summary>Detalle de una OM: resumen, instrumentos (recibidos o pendientes) y recepciones registradas. Solo de una OM del técnico.</summary>
public class ObtenerDetalleRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleRecepcionOmMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0
            ? Task.FromResult(new RespuestaDto<DetalleRecepcionOmMovilDto>(1, "Orden de metrología no encontrada o no asignada a tu usuario."))
            : repositorio.ObtenerDetalleAsync(idUsuario, idOs, ct);
}

/// <summary>Sube una foto de recepción de un instrumento (JPEG de la cámara de la app). Queda pendiente hasta que se registre la recepción. Sin IA.</summary>
public class SubirFotoRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<FotoRecepcionOmMovilDto>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, Stream? archivo, long tamano, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0) return new(1, "Instrumento no encontrado.");
        var (bytes, error) = await EntradaRecepcionOmMovil.LeerFotoAsync(archivo, tamano, ct);
        if (bytes is null) return new(1, error ?? "La foto no es válida.");

        var ruta = $"recepcion-om/{idOs}/{idOsEquipo}/foto_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.jpg";
        await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);
        RespuestaDto<FotoRecepcionOmMovilDto> r;
        try { r = await repositorio.RegistrarFotoAsync(idUsuario, idOs, idOsEquipo, ruta, ct); }
        catch { await almacen.EliminarAsync(ruta, CancellationToken.None); throw; }
        if (r.IdTipoMensaje != 2) await almacen.EliminarAsync(ruta, CancellationToken.None);
        return r;
    }
}

/// <summary>Quita una foto de recepción todavía no registrada (y borra su archivo).</summary>
public class QuitarFotoRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<object>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, long idFoto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0 || idFoto <= 0) return new(1, "Foto no encontrada.");
        var r = await repositorio.QuitarFotoAsync(idUsuario, idOs, idOsEquipo, idFoto, ct);
        if (r.IdTipoMensaje != 2) return new(r.IdTipoMensaje, r.Mensaje);
        if (!string.IsNullOrEmpty(r.Datos)) await almacen.EliminarAsync(r.Datos, CancellationToken.None);
        return new(2, r.Mensaje);
    }
}

/// <summary>Fotos pendientes (sin registrar) del técnico para un instrumento: para reanudar si cerró la pantalla a medias.</summary>
public class ObtenerFotosRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio)
{
    public Task<RespuestaDto<List<FotoRecepcionOmMovilDto>>> EjecutarAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 || idOs <= 0 || idOsEquipo <= 0
            ? Task.FromResult(new RespuestaDto<List<FotoRecepcionOmMovilDto>>(1, "Instrumento no encontrado."))
            : repositorio.ObtenerFotosAsync(idUsuario, idOs, idOsEquipo, ct);
}

/// <summary>Abre el JPEG de una foto de recepción (solo del técnico, o de una recepción de una OM suya).</summary>
public class ObtenerArchivoFotoRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<(Stream? Contenido, string? Tipo, string? Mensaje)> EjecutarAsync(long idUsuario, long idFoto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idFoto <= 0) return (null, null, "Foto no encontrada.");
        var r = await repositorio.ObtenerRutaFotoAsync(idUsuario, idFoto, ct);
        if (r.IdTipoMensaje != 2 || string.IsNullOrEmpty(r.Datos)) return (null, null, r.Mensaje);
        var s = await almacen.AbrirLecturaAsync(r.Datos, ct);
        return s is null ? (null, null, "El archivo ya no está disponible.") : (s, "image/jpeg", null);
    }
}

/// <summary>«Escanear etiqueta del instrumento»: resuelve el texto leído al instrumento de esta OM.</summary>
public class BuscarQrRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio)
{
    public const int MaxTexto = 300;

    public Task<RespuestaDto<InstrumentoQrRecepcionOmMovilDto>> EjecutarAsync(long idUsuario, long idOs, string? texto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return Task.FromResult(new RespuestaDto<InstrumentoQrRecepcionOmMovilDto>(1, "Orden de metrología no encontrada o no asignada a tu usuario."));
        var t = EntradaObjetivosMovil.Limpiar(texto);
        if (t is not { Length: <= MaxTexto }) return Task.FromResult(new RespuestaDto<InstrumentoQrRecepcionOmMovilDto>(1, "El código leído no es válido."));
        return repositorio.BuscarQrAsync(idUsuario, idOs, t, ct);
    }
}

/// <summary>
/// Genera la constancia de recepción (PDF), la guarda en el almacén y deja su ruta en la recepción. Si se pide y CONSTANCIA_ENVIO_CORREO = 1 la envía al contacto del cliente
/// (best-effort: nunca revierte la recepción). Lo usan «Registrar recepción» y la descarga cuando el archivo ya no está.
/// </summary>
public class EmitirConstanciaRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio, IGeneradorConstanciaRecepcionOmPdf pdf, IAlmacenArchivos almacen, NotificadorCorreo correo)
{
    public async Task<(byte[]? Bytes, bool CorreoEnviado)> EjecutarAsync(long idUsuario, long idRecepcion, ConstanciaRecepcionOmDto? datos, bool enviarCorreo, CancellationToken ct)
    {
        string? ruta = null;
        try
        {
            if (datos is null)
            {
                var r = await repositorio.ObtenerConstanciaAsync(idUsuario, idRecepcion, ct);
                if (r.IdTipoMensaje != 2 || r.Datos is null) return (null, false);
                datos = r.Datos;
            }
            var c = datos.Cabecera;
            var bytes = pdf.Generar(datos);
            ruta = $"recepcion-om/constancias/recepcion_{idRecepcion}_{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}.pdf";
            await almacen.GuardarAsync(ruta, new MemoryStream(bytes), ct);

            var enviado = false;
            if (enviarCorreo && c.EnvioActivo && !string.IsNullOrWhiteSpace(c.ContactoCorreo))
            {
                try
                {
                    var nombre = c.ContactoNombre ?? "cliente";
                    var texto = $"Estimado(a) {nombre}:\n\nAdjuntamos la constancia de recepción de instrumentos de la orden {c.NumeroOm} (guía {c.Guia}).\n\nTotal Weight";
                    var html = $"<p>Estimado(a) {System.Net.WebUtility.HtmlEncode(nombre)}:</p><p>Adjuntamos la constancia de recepción de instrumentos de la orden <b>{System.Net.WebUtility.HtmlEncode(c.NumeroOm)}</b> (guía {System.Net.WebUtility.HtmlEncode(c.Guia ?? "—")}).</p><p>Total Weight</p>";
                    var envio = await correo.EnviarAsync("constancia_recepcion_om",
                        new MensajeCorreoDto(c.ContactoCorreo.Trim(), c.ContactoNombre, $"Constancia de recepción {c.NumeroOm}", html, texto,
                            Adjuntos: [new AdjuntoCorreoDto($"constancia-recepcion-{c.NumeroOm}.pdf", Convert.ToBase64String(bytes))]),
                        "orden_servicio", null, idUsuario, ct);
                    enviado = envio.Enviado;
                }
                catch (Exception) when (!ct.IsCancellationRequested)
                {
                    enviado = false;
                }
            }

            var guardada = await repositorio.GuardarConstanciaAsync(idUsuario, idRecepcion, ruta, enviado, ct);
            if (guardada.IdTipoMensaje != 2)
            {
                await almacen.EliminarAsync(ruta, CancellationToken.None);
                return (bytes, enviado);
            }
            if (!string.IsNullOrEmpty(guardada.Datos)) await almacen.EliminarAsync(guardada.Datos, CancellationToken.None);
            return (bytes, enviado);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            if (ruta is not null) await almacen.EliminarAsync(ruta, CancellationToken.None);
            return (null, false);
        }
    }
}

/// <summary>
/// «Registrar recepción»: valida la entrada, registra la recepción con el SP (que decide parcial / observado / conforme, notifica a Programación si es parcial y deja todo en una transacción)
/// y después genera y envía la constancia (best-effort).
/// </summary>
public class RegistrarRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio, EmitirConstanciaRecepcionOmMovilCasoDeUso constancia)
{
    public async Task<RespuestaDto<ResultadoRecepcionOmMovilDto>> EjecutarAsync(long idUsuario, long idOs, PeticionRecepcionOmMovilDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0) return new(1, "Orden de metrología no encontrada o no asignada a tu usuario.");
        var (cmd, error) = EntradaRecepcionOmMovil.Validar(d);
        if (cmd is null) return new(1, error ?? "Datos incompletos.");

        var r = await repositorio.RegistrarAsync(idUsuario, idOs, cmd.NumeroGuia, cmd.MedioEntrega, cmd.EntregoNombre, cmd.EntregoCargo, cmd.MotivoParcial, cmd.InstrumentosJson, cmd.FirmaJson, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        // La recepción ya está guardada: la constancia y el correo no la pueden revertir
        var (_, correoEnviado) = await constancia.EjecutarAsync(idUsuario, r.Datos.IdRecepcion, null, enviarCorreo: true, ct);
        var x = r.Datos;
        return new(2, r.Mensaje, new ResultadoRecepcionOmMovilDto(x.IdRecepcion, x.Estado, x.Parcial, x.InstrumentosRecibidos, x.InstrumentosPendientes, correoEnviado, r.Mensaje));
    }
}

/// <summary>PDF de la constancia de una recepción: el guardado o, si el archivo ya no está, uno nuevo con los mismos datos. Solo de una OM del técnico.</summary>
public class ObtenerConstanciaRecepcionOmMovilCasoDeUso(IRecepcionOmMovilRepositorio repositorio, IAlmacenArchivos almacen, EmitirConstanciaRecepcionOmMovilCasoDeUso emitir)
{
    public async Task<RespuestaDto<byte[]>> EjecutarAsync(long idUsuario, long idRecepcion, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idRecepcion <= 0) return new(1, "Constancia no encontrada.");
        var r = await repositorio.ObtenerConstanciaAsync(idUsuario, idRecepcion, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        if (!string.IsNullOrEmpty(r.Datos.Cabecera.RutaConstancia))
        {
            await using var s = await almacen.AbrirLecturaAsync(r.Datos.Cabecera.RutaConstancia, ct);
            if (s is not null)
            {
                using var m = new MemoryStream();
                await s.CopyToAsync(m, ct);
                if (m.Length > 0) return new(2, "Éxito.", m.ToArray());
            }
        }

        var (bytes, _) = await emitir.EjecutarAsync(idUsuario, idRecepcion, r.Datos, enviarCorreo: false, ct);
        return bytes is null ? new(3, "No se pudo generar la constancia.") : new(2, "Éxito.", bytes);
    }
}
