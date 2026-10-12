using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ══════════════════════ HU-17 — Bandeja de Seguimiento Comercial ══════════════════════

public class ObtenerBandejaSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    private static readonly string[] Estados =
    [
        "", "abiertas", "en_seguimiento", "sin_respuesta", "requiere_ajuste", "vencidos",
        "aceptada", "rechazada", "oc_pendientes", "aceptadas_mes", "rechazadas_mes", "todas",
    ];

    public Task<RespuestaDto<BandejaSeguimientoDto>> EjecutarAsync(
        FiltrosBandejaSeguimientoDto f, long idUsuario, CancellationToken ct = default)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return Task.FromResult(new RespuestaDto<BandejaSeguimientoDto>(1,
                "Estado no válido. Use abiertas, en_seguimiento, sin_respuesta, requiere_ajuste, vencidos, " +
                "aceptada, rechazada, oc_pendientes, aceptadas_mes, rechazadas_mes o todas."));

        var filtros = f with
        {
            IdResponsable = f.IdResponsable is > 0 ? f.IdResponsable : null,
            Estado        = estado,
            Busqueda      = string.IsNullOrWhiteSpace(f.Busqueda) ? null : f.Busqueda.Trim(),
            Pagina        = Math.Max(f.Pagina, 1),
            PorPagina     = Math.Clamp(f.PorPagina, 1, 100),
        };
        return repositorio.ObtenerBandejaAsync(filtros, idUsuario, ct);
    }
}

// ══════════════════════ HU-18 — Vista Detalle del Seguimiento ══════════════════════

public class ObtenerDetalleSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleSeguimientoDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<DetalleSeguimientoDto>(1, "Propuesta no válida."));
        return repositorio.ObtenerDetalleAsync(idPropuesta, idUsuario, ct);
    }
}

// ══════════════════════ HU-19 — Registro de acciones de seguimiento ══════════════════════

/// <summary>Catálogos, contactos, responsables, plantillas y borrador para los modales de registro.</summary>
public class PrepararRegistroSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionRegistroSeguimientoDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<PreparacionRegistroSeguimientoDto>(1, "Propuesta no válida."));
        return repositorio.PrepararRegistroAsync(idPropuesta, idUsuario, ct);
    }
}

/// <summary>Validaciones de forma comunes (el SP vuelve a validar todo contra la BD).</summary>
internal static class ValidacionSeguimiento
{
    public static string? ProximaAccion(bool programar, ProximaAccionEntradaDto? a)
    {
        if (!programar) return null;
        if (a is null)                                 return "Complete los datos de la próxima acción.";
        if (a.IdTipoAccion is null or <= 0)            return "Seleccione el tipo de tarea de la próxima acción.";
        if (a.Fecha is null)                           return "Indique la fecha y hora de la próxima acción.";
        if (a.IdResponsable is null or <= 0)           return "Seleccione el responsable de la próxima acción.";
        if (a.IdPrioridad is null or <= 0)             return "Seleccione la prioridad de la próxima acción.";
        if ((a.Detalle?.Trim().Length ?? 0) > 200)     return "El detalle de la próxima acción admite hasta 200 caracteres.";
        return null;
    }

    public static string? Notas(string? notas) =>
        (notas?.Trim().Length ?? 0) > 4000 ? "Las notas admiten hasta 4000 caracteres." : null;
}

/// <summary>Registro general: tipo de seguimiento, resultado, contacto, notas y próxima acción opcional.</summary>
public class RegistrarSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public async Task<RespuestaDto<ResultadoRegistroSeguimientoDto>> EjecutarAsync(
        long idPropuesta, RegistrarSeguimientoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)              return new(1, "Propuesta no válida.");
        if (dto.IdCanal is null or <= 0)   return new(1, "Seleccione el tipo de seguimiento.");
        if (dto.IdResultado is null or <= 0) return new(1, "Seleccione el resultado del seguimiento.");
        if (ValidacionSeguimiento.Notas(dto.Notas) is { } e1) return new(1, e1);
        if (ValidacionSeguimiento.ProximaAccion(dto.ProgramarProximaAccion, dto.ProximaAccion) is { } e2) return new(1, e2);

        var comando = new ComandoRegistroSeguimiento(
            dto.IdCanal, null, dto.IdResultado, null, dto.IdContacto, dto.FechaInteraccion, null,
            dto.Notas?.Trim(), null, dto.ProgramarProximaAccion, dto.ProximaAccion, dto.EjecutaAccionPendiente);

        var r = await repositorio.RegistrarAsync(idPropuesta, comando, idUsuario, false, ct);
        return r.IdTipoMensaje == 2
            ? new(2, r.Mensaje, new ResultadoRegistroSeguimientoDto(r.Datos))
            : new(r.IdTipoMensaje, r.Mensaje);
    }
}

/// <summary>Registro específico de llamada: fecha y hora, duración, resultado y notas obligatorias.</summary>
public class RegistrarLlamadaSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public async Task<RespuestaDto<ResultadoRegistroSeguimientoDto>> EjecutarAsync(
        long idPropuesta, RegistrarLlamadaDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)                  return new(1, "Propuesta no válida.");
        if (dto.FechaInteraccion is null)      return new(1, "Indique la fecha y hora de la llamada.");
        if (dto.DuracionMinutos is null or < 0 or > 600)
                                               return new(1, "Indique la duración de la llamada en minutos (0 a 600).");
        if (dto.IdResultado is null or <= 0)   return new(1, "Seleccione el resultado de la llamada.");
        if ((dto.Notas?.Trim().Length ?? 0) < 5) return new(1, "Describa los puntos clave de la llamada (mínimo 5 caracteres).");
        if (ValidacionSeguimiento.Notas(dto.Notas) is { } e1) return new(1, e1);
        if (ValidacionSeguimiento.ProximaAccion(dto.ProgramarProximaAccion, dto.ProximaAccion) is { } e2) return new(1, e2);

        var comando = new ComandoRegistroSeguimiento(
            null, "LLAMADA", dto.IdResultado, null, dto.IdContacto, dto.FechaInteraccion, dto.DuracionMinutos,
            dto.Notas?.Trim(), null, dto.ProgramarProximaAccion, dto.ProximaAccion, dto.EjecutaAccionPendiente);

        var r = await repositorio.RegistrarAsync(idPropuesta, comando, idUsuario, false, ct);
        return r.IdTipoMensaje == 2
            ? new(2, r.Mensaje, new ResultadoRegistroSeguimientoDto(r.Datos))
            : new(r.IdTipoMensaje, r.Mensaje);
    }
}

/// <summary>Validación y normalización del correo (destinatarios, asunto y HTML seguro).</summary>
internal static class ValidacionCorreoSeguimiento
{
    public const int MaximoDestinatarios = 20;

    public static (ComandoCorreoSeguimiento? Comando, string? Error) Normalizar(CorreoSeguimientoDto dto, bool exigirCompleto)
    {
        var para = Limpiar(dto.Para);
        var cc   = Limpiar(dto.Cc).Where(c => !para.Any(p => p.Correo.Equals(c.Correo, StringComparison.OrdinalIgnoreCase))).ToList();

        var invalido = para.Concat(cc).FirstOrDefault(d => !EsCorreo(d.Correo));
        if (invalido is not null)
            return (null, $"El correo \"{invalido.Correo}\" no es válido.");
        if (para.Count + cc.Count > MaximoDestinatarios)
            return (null, $"Máximo {MaximoDestinatarios} destinatarios entre Para y CC.");

        var asunto = dto.Asunto?.Trim() ?? "";
        var cuerpo = Servicios.HtmlCorreoSeguro.Limpiar(dto.CuerpoHtml);

        if (asunto.Length > 300)    return (null, "El asunto admite hasta 300 caracteres.");
        if (cuerpo.Length > 200_000) return (null, "El contenido del correo es demasiado grande.");

        if (exigirCompleto)
        {
            if (para.Count == 0)        return (null, "Agregue al menos un destinatario.");
            if (asunto.Length == 0)     return (null, "Indique el asunto del correo.");
            if (Servicios.HtmlCorreoSeguro.ATexto(cuerpo).Length == 0)
                                        return (null, "Escriba el contenido del correo.");
        }

        return (new ComandoCorreoSeguimiento(dto.IdCorreo is > 0 ? dto.IdCorreo : null,
                                             dto.IdPlantilla is > 0 ? dto.IdPlantilla : null,
                                             para, cc, asunto, cuerpo), null);
    }

    private static List<DestinatarioSeguimientoDto> Limpiar(List<DestinatarioSeguimientoDto>? lista) =>
        (lista ?? [])
            .Where(d => !string.IsNullOrWhiteSpace(d.Correo))
            .Select(d => d with { Correo = d.Correo.Trim(), Nombre = string.IsNullOrWhiteSpace(d.Nombre) ? null : d.Nombre.Trim() })
            .DistinctBy(d => d.Correo.ToLowerInvariant())
            .ToList();

    private static bool EsCorreo(string correo) =>
        correo.Length <= 200 && System.Net.Mail.MailAddress.TryCreate(correo, out var m) && m.Address == correo;
}

/// <summary>"Guardar borrador" del modal de correo.</summary>
public class GuardarBorradorCorreoSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public async Task<RespuestaDto<CorreoSeguimientoGuardadoDto>> EjecutarAsync(
        long idPropuesta, CorreoSeguimientoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0) return new(1, "Propuesta no válida.");
        var (comando, error) = ValidacionCorreoSeguimiento.Normalizar(dto, exigirCompleto: false);
        if (comando is null) return new(1, error!);
        return await repositorio.GuardarCorreoAsync(idPropuesta, comando, "borrador", null, null, idUsuario, ct);
    }
}

/// <summary>
/// "Enviar y registrar seguimiento": valida el seguimiento, guarda el correo, lo envía (Brevo) y,
/// si salió, registra el seguimiento con canal CORREO enlazado al correo. Si el envío falla,
/// el correo queda como borrador con el error y no se registra el seguimiento.
/// </summary>
public class EnviarCorreoSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio, NotificadorCorreo notificador)
{
    public async Task<RespuestaDto<ResultadoRegistroSeguimientoDto>> EjecutarAsync(
        long idPropuesta, CorreoSeguimientoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0) return new(1, "Propuesta no válida.");
        var (correo, error) = ValidacionCorreoSeguimiento.Normalizar(dto, exigirCompleto: true);
        if (correo is null) return new(1, error!);
        if (ValidacionSeguimiento.ProximaAccion(dto.ProgramarProximaAccion, dto.ProximaAccion) is { } e) return new(1, e);

        var texto = Servicios.HtmlCorreoSeguro.ATexto(correo.CuerpoHtml);
        var notas = texto.Length > 4000 ? texto[..3997] + "..." : texto;
        var idContacto = dto.IdContacto ?? correo.Para.FirstOrDefault(p => p.IdContacto is > 0)?.IdContacto;

        ComandoRegistroSeguimiento Comando(long? idCorreo = null, string? proveedor = null, string? idMensaje = null) =>
            new(null, "CORREO", dto.IdResultado is > 0 ? dto.IdResultado : null,
                dto.IdResultado is > 0 ? null : "CORREO_ENVIADO",
                idContacto, null, null, notas, correo.Asunto,
                dto.ProgramarProximaAccion, dto.ProximaAccion, dto.EjecutaAccionPendiente,
                idCorreo, proveedor, idMensaje);

        // 1. Validar el seguimiento antes de enviar nada
        var validacion = await repositorio.RegistrarAsync(idPropuesta, Comando(), idUsuario, true, ct);
        if (validacion.IdTipoMensaje != 2) return new(validacion.IdTipoMensaje, validacion.Mensaje);

        // 2. Guardar el correo (queda como borrador hasta confirmar el envío)
        var guardado = await repositorio.GuardarCorreoAsync(idPropuesta, correo, "borrador", null, null, idUsuario, ct);
        if (guardado.IdTipoMensaje != 2 || guardado.Datos is null) return new(guardado.IdTipoMensaje, guardado.Mensaje);
        var g = guardado.Datos;

        // 3. Enviar: desde el remitente del sistema, con el nombre del usuario y "responder a" su correo
        var primero = correo.Para[0];
        var mensaje = new MensajeCorreoDto(
            primero.Correo, primero.Nombre, correo.Asunto, correo.CuerpoHtml, texto,
            ParaAdicionales:  correo.Para.Skip(1).Select(d => new DestinatarioCorreoDto(d.Correo, d.Nombre)).ToList(),
            Cc:               correo.Cc.Select(d => new DestinatarioCorreoDto(d.Correo, d.Nombre)).ToList(),
            ResponderA:       g.CorreoUsuario,
            NombreResponderA: g.Usuario,
            NombreRemitente:  $"{g.Usuario} | Total Weight");

        var envio = await notificador.EnviarAsync("seguimiento_propuesta", mensaje, "propuesta", idPropuesta, idUsuario, ct);
        if (!envio.Enviado)
        {
            await repositorio.GuardarCorreoAsync(idPropuesta, correo with { IdCorreo = g.IdCorreo },
                                                 "error", envio.Proveedor, envio.Error, idUsuario, CancellationToken.None);
            return new(1, $"No se pudo enviar el correo: {envio.Error}. Quedó guardado como borrador.");
        }

        // 4. Registrar el seguimiento enlazado al correo
        var registro = await repositorio.RegistrarAsync(idPropuesta, Comando(g.IdCorreo, envio.Proveedor, envio.IdMensaje),
                                                        idUsuario, false, CancellationToken.None);
        return registro.IdTipoMensaje == 2
            ? new(2, "Correo enviado y seguimiento registrado.", new ResultadoRegistroSeguimientoDto(registro.Datos, g.IdCorreo))
            : new(3, $"El correo se envió, pero no se pudo registrar el seguimiento: {registro.Mensaje}");
    }
}

/// <summary>Documentos adjuntos (opcionales) de un seguimiento: hasta 5 archivos de 10 MB.</summary>
public class SubirAdjuntosSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio, IAlmacenArchivos almacen)
{
    public const long TamanoMaximoBytes = 10 * 1024 * 1024;
    public const int  MaximoArchivos    = 5;

    private static readonly Dictionary<string, string> Tipos = new(StringComparer.OrdinalIgnoreCase)
    {
        [".pdf"]  = "application/pdf",
        [".png"]  = "image/png",
        [".jpg"]  = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".doc"]  = "application/msword",
        [".docx"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        [".xls"]  = "application/vnd.ms-excel",
        [".xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        [".msg"]  = "application/vnd.ms-outlook",
        [".eml"]  = "message/rfc822",
        [".txt"]  = "text/plain",
    };

    public record ArchivoEntrada(Stream Contenido, string? NombreArchivo, long TamanoBytes);

    public async Task<RespuestaDto<List<AdjuntoSeguimientoDto>>> EjecutarAsync(
        long idSeguimiento, IReadOnlyList<ArchivoEntrada> archivos, long idUsuario, CancellationToken ct = default)
    {
        if (idSeguimiento <= 0)        return new(1, "Seguimiento no válido.");
        if (archivos.Count == 0)       return new(1, "Seleccione al menos un archivo.");
        if (archivos.Count > MaximoArchivos) return new(1, $"Máximo {MaximoArchivos} archivos por seguimiento.");

        foreach (var a in archivos)
        {
            var ext = Path.GetExtension(a.NombreArchivo ?? "");
            if (!Tipos.ContainsKey(ext))
                return new(1, $"\"{a.NombreArchivo}\": tipo de archivo no permitido (PDF, imágenes, Word, Excel, correo o texto).");
            if (a.TamanoBytes <= 0 || a.TamanoBytes > TamanoMaximoBytes)
                return new(1, $"\"{a.NombreArchivo}\": el archivo debe pesar entre 1 byte y 10 MB.");
        }

        var resultado = new List<AdjuntoSeguimientoDto>();
        foreach (var a in archivos)
        {
            var validacion = await repositorio.RegistrarAdjuntoAsync(idSeguimiento, "", "", "", 0, idUsuario, true, ct);
            if (validacion.IdTipoMensaje != 2)
                return resultado.Count == 0
                    ? new(validacion.IdTipoMensaje, validacion.Mensaje)
                    : new(1, $"Se guardaron {resultado.Count} archivo(s). {validacion.Mensaje}", resultado);

            var ext    = Path.GetExtension(a.NombreArchivo!).ToLowerInvariant();
            var nombre = NormalizarNombre(a.NombreArchivo!, ext);
            var ruta   = $"seguimientos/{idSeguimiento}/{DateTime.UtcNow:yyyyMMddHHmmss}_{Guid.NewGuid():N}{ext}";

            await almacen.GuardarAsync(ruta, a.Contenido, ct);
            var registro = await repositorio.RegistrarAdjuntoAsync(idSeguimiento, nombre, ruta, Tipos[ext], a.TamanoBytes, idUsuario, false, ct);
            if (registro.IdTipoMensaje != 2)
            {
                await almacen.EliminarAsync(ruta, CancellationToken.None);
                return new(registro.IdTipoMensaje, registro.Mensaje, resultado);
            }
            resultado.Add(new AdjuntoSeguimientoDto(registro.Datos, nombre, a.TamanoBytes, $"/api/crm/seguimiento/adjuntos/{registro.Datos}"));
        }
        return new(2, resultado.Count == 1 ? "Adjunto guardado." : $"{resultado.Count} adjuntos guardados.", resultado);
    }

    private static string NormalizarNombre(string nombreArchivo, string ext)
    {
        var nombre = Path.GetFileName(nombreArchivo).Trim();
        foreach (var c in Path.GetInvalidFileNameChars())
            nombre = nombre.Replace(c, '_');
        if (nombre.Length == 0) nombre = "adjunto" + ext;
        if (nombre.Length > 255) nombre = nombre[..(255 - ext.Length)] + ext;
        return nombre;
    }
}

/// <summary>Abre un adjunto de seguimiento para verlo o descargarlo.</summary>
public class ObtenerAdjuntoSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio, IAlmacenArchivos almacen)
{
    public async Task<RespuestaDto<ArchivoDescargaDto>> EjecutarAsync(long idAdjunto, long idUsuario, CancellationToken ct = default)
    {
        if (idAdjunto <= 0) return new(1, "Adjunto no válido.");
        var ruta = await repositorio.ObtenerAdjuntoAsync(idAdjunto, idUsuario, ct);
        if (ruta.IdTipoMensaje != 2 || ruta.Datos is null)
            return new(ruta.IdTipoMensaje, ruta.Mensaje);

        var contenido = await almacen.AbrirLecturaAsync(ruta.Datos.Ruta, ct);
        if (contenido is null)
            return new(1, "El adjunto está registrado pero no se encontró en el almacenamiento.");

        return new(2, ruta.Mensaje, new ArchivoDescargaDto(contenido, ruta.Datos.NombreArchivo, ruta.Datos.TipoContenido));
    }
}

// ══════════════════════ HU-20 — Reprogramación de acciones ══════════════════════

/// <summary>Acción actual, catálogos, responsables, motivos e historial para el modal de reprogramación.</summary>
public class PrepararReprogramacionSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionReprogramacionDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return Task.FromResult(new RespuestaDto<PreparacionReprogramacionDto>(1, "Propuesta no válida."));
        return repositorio.PrepararReprogramacionAsync(idPropuesta, idUsuario, ct);
    }
}

/// <summary>
/// Reprograma la próxima acción pendiente: tipo, nueva fecha y hora, prioridad, responsable,
/// motivo (radio buttons) y detalle obligatorio. Guarda el historial con la acción anterior.
/// </summary>
public class ReprogramarAccionSeguimientoCasoDeUso(ISeguimientoComercialRepositorio repositorio)
{
    public async Task<RespuestaDto<ResultadoReprogramacionDto>> EjecutarAsync(
        long idPropuesta, ReprogramarAccionDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)                    return new(1, "Propuesta no válida.");
        if (dto.IdTipoAccion is null or <= 0)    return new(1, "Seleccione el tipo de acción.");
        if (dto.Fecha is null)                   return new(1, "Indique la nueva fecha y hora.");
        if (dto.IdPrioridad is null or <= 0)     return new(1, "Seleccione la prioridad.");
        if (dto.IdResponsable is null or <= 0)   return new(1, "Seleccione el responsable.");
        if (dto.IdMotivo is null or <= 0)        return new(1, "Seleccione el motivo de la reprogramación.");

        var detalle = dto.Detalle?.Trim() ?? "";
        if (detalle.Length < 10)  return new(1, "Explique el motivo de la reprogramación (mínimo 10 caracteres).");
        if (detalle.Length > 500) return new(1, "El detalle admite hasta 500 caracteres.");

        var r = await repositorio.ReprogramarAccionAsync(idPropuesta, dto with { Detalle = detalle }, idUsuario, ct);
        return r.IdTipoMensaje == 2
            ? new(2, r.Mensaje, new ResultadoReprogramacionDto(r.Datos))
            : new(r.IdTipoMensaje, r.Mensaje);
    }
}
