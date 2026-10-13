using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ─────────────────────────────────────────────────────────────────────────────
// HU-12 — Envío a Visto Bueno y Anulación de Propuesta. Validaciones de forma
// aquí. Las de negocio (estado, última versión, requisitos, aprobador, SLA,
// permisos, OC vinculada) están en SP_EnviarVistoBuenoPropuesta y SP_AnularPropuesta.
// ─────────────────────────────────────────────────────────────────────────────

public class PrepararVistoBuenoPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<VistoBuenoPropuestaDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<VistoBuenoPropuestaDto>(1, "Indique la propuesta."))
            : repositorio.EnviarVistoBuenoAsync(idPropuesta, null, soloPreparar: true, idUsuario, ct);
}

public class EnviarVistoBuenoPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    private const int MaxComentario = 2000;

    public async Task<RespuestaDto<VistoBuenoPropuestaDto>> EjecutarAsync(
        long idPropuesta, EnviarVistoBuenoPropuestaDto? dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return new RespuestaDto<VistoBuenoPropuestaDto>(1, "Indique la propuesta.");

        var comentario = dto?.Comentario?.Trim();
        if (comentario is { Length: > MaxComentario })
            return new RespuestaDto<VistoBuenoPropuestaDto>(1, $"El comentario no puede superar los {MaxComentario} caracteres.");

        return await repositorio.EnviarVistoBuenoAsync(idPropuesta, comentario, soloPreparar: false, idUsuario, ct);
    }
}

public class PrepararAnulacionPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<AnulacionPropuestaDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<AnulacionPropuestaDto>(1, "Indique la propuesta."))
            : repositorio.AnularPropuestaAsync(idPropuesta, null, null, false, soloPreparar: true, idUsuario, ct);
}

public class AnularPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    private const int MinJustificacion = 20;
    private const int MaxJustificacion = 2000;

    public async Task<RespuestaDto<AnulacionPropuestaDto>> EjecutarAsync(
        long idPropuesta, AnularPropuestaDto? dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return new RespuestaDto<AnulacionPropuestaDto>(1, "Indique la propuesta.");
        if (dto is null)
            return new RespuestaDto<AnulacionPropuestaDto>(1, "Indique los datos de la anulación.");
        if (dto.IdMotivoAnulacion is null or <= 0)
            return new RespuestaDto<AnulacionPropuestaDto>(1, "Seleccione el motivo de anulación.");

        var justificacion = dto.Justificacion?.Trim() ?? "";
        if (justificacion.Length < MinJustificacion)
            return new RespuestaDto<AnulacionPropuestaDto>(1,
                $"La justificación detallada es obligatoria (mínimo {MinJustificacion} caracteres).");
        if (justificacion.Length > MaxJustificacion)
            return new RespuestaDto<AnulacionPropuestaDto>(1,
                $"La justificación no puede superar los {MaxJustificacion} caracteres.");
        if (!dto.ConfirmacionCritica)
            return new RespuestaDto<AnulacionPropuestaDto>(1, "Marque la Confirmación Crítica para anular la propuesta.");

        return await repositorio.AnularPropuestaAsync(
            idPropuesta, dto.IdMotivoAnulacion, justificacion, true, soloPreparar: false, idUsuario, ct);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HU-10b — Envío de propuesta al cliente (post VB aprobado)
// ─────────────────────────────────────────────────────────────────────────────

public class PrepararEnvioClienteCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionEnvioClienteDto>> EjecutarAsync(long idPropuesta, long idUsuario, CancellationToken ct = default)
        => idPropuesta <= 0
            ? Task.FromResult(new RespuestaDto<PreparacionEnvioClienteDto>(1, "Indique la propuesta."))
            : repositorio.PrepararEnvioClienteAsync(idPropuesta, idUsuario, ct);
}

public class EnviarPropuestaClienteCasoDeUso(
    IPropuestasRepositorio       repositorio,
    NotificadorCorreo            notificador,
    GenerarPdfPropuestaCasoDeUso generarPdf)
{
    private const int MaxAsunto = 300;
    private const int MaxCuerpo = 50_000;

    public async Task<RespuestaDto<EnvioPropuestaClienteDto>> EjecutarAsync(
        long idPropuesta, EnviarPropuestaClienteDto? dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, "Indique la propuesta.");
        if (dto is null)
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, "Indique los datos del correo.");

        var destinatarios = (dto.Para ?? [])
            .Where(d => !string.IsNullOrWhiteSpace(d.Correo))
            .Select(d => new DestinatarioEnvioClienteDto(d.Correo.Trim(), d.Nombre?.Trim(), d.IdContacto))
            .ToList();
        if (destinatarios.Count == 0)
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, "Agregue al menos un destinatario (PARA).");

        var asunto = dto.Asunto?.Trim() ?? "";
        if (string.IsNullOrEmpty(asunto))
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, "El asunto es obligatorio.");
        if (asunto.Length > MaxAsunto)
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, $"El asunto no puede superar los {MaxAsunto} caracteres.");

        var cuerpo = dto.CuerpoHtml?.Trim() ?? "";
        if (string.IsNullOrEmpty(cuerpo))
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, "El cuerpo del correo es obligatorio.");
        if (cuerpo.Length > MaxCuerpo)
            return new RespuestaDto<EnvioPropuestaClienteDto>(1, $"El cuerpo del correo no puede superar los {MaxCuerpo} caracteres.");

        // 1. Marca la propuesta como 'enviado' (valida permisos + autoría + estado 'aprobado' en el SP).
        var r = await repositorio.EnviarPropuestaClienteAsync(idPropuesta, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return r;

        // 2. Envía el correo via Brevo (no revierte el estado si falla — se marca en el resultado).
        var cc = (dto.Cc ?? [])
            .Where(d => !string.IsNullOrWhiteSpace(d.Correo))
            .Select(d => new DestinatarioCorreoDto(d.Correo.Trim(), d.Nombre?.Trim()))
            .ToList();

        var primero  = destinatarios[0];
        var adicionales = destinatarios.Skip(1)
            .Select(d => new DestinatarioCorreoDto(d.Correo, d.Nombre))
            .ToList();

        // Genera el PDF de la propuesta y lo adjunta al correo. Si el PDF falla,
        // el correo igual sale sin adjunto (se avisa en el error).
        var adjuntos = new List<AdjuntoCorreoDto>();
        var pdfResp = await generarPdf.EjecutarAsync(idPropuesta, ct);
        string? avisoPdf = null;
        if (pdfResp.IdTipoMensaje == 2 && pdfResp.Datos is { Length: > 0 })
        {
            var nombreArchivo = $"{r.Datos.Numero}-v{r.Datos.Version}.pdf";
            adjuntos.Add(new AdjuntoCorreoDto(nombreArchivo, Convert.ToBase64String(pdfResp.Datos)));
        }
        else
        {
            avisoPdf = $"No se pudo adjuntar el PDF ({pdfResp.Mensaje}).";
        }

        var mensaje = new MensajeCorreoDto(
            Para:             primero.Correo,
            NombrePara:       primero.Nombre,
            Asunto:           asunto,
            Html:             cuerpo,
            Texto:            SinHtml(cuerpo),
            ParaAdicionales:  adicionales.Count > 0 ? adicionales : null,
            Cc:               cc.Count > 0 ? cc : null,
            Adjuntos:         adjuntos.Count > 0 ? adjuntos : null);

        var envio = await notificador.EnviarAsync("envio_propuesta_cliente", mensaje, "propuesta", idPropuesta, idUsuario, ct);
        r.Datos.CorreoEnviado = envio.Enviado;
        r.Datos.CorreoError   = avisoPdf is null ? envio.Error : $"{envio.Error ?? ""} {avisoPdf}".Trim();
        return r;
    }

    private static string SinHtml(string html)
    {
        // Strip HTML muy básico para el fallback plain-text del correo.
        var limpio = System.Text.RegularExpressions.Regex.Replace(html, "<br\\s*/?>", "\n",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        limpio = System.Text.RegularExpressions.Regex.Replace(limpio, "</p>", "\n\n",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        limpio = System.Text.RegularExpressions.Regex.Replace(limpio, "<[^>]+>", string.Empty);
        return System.Net.WebUtility.HtmlDecode(limpio).Trim();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HU-13b — Solicitar revocación de VB (comercial)
// ─────────────────────────────────────────────────────────────────────────────

public class SolicitarRevocacionVbCasoDeUso(IPropuestasRepositorio repositorio)
{
    private const int MinMotivo = 10;
    private const int MaxMotivo = 2000;

    public async Task<RespuestaDto<ResultadoSolicitarRevocacionVbDto>> EjecutarAsync(
        long idPropuesta, SolicitarRevocacionVbDto? dto, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return new RespuestaDto<ResultadoSolicitarRevocacionVbDto>(1, "Indique la propuesta.");

        var motivo = dto?.Motivo?.Trim() ?? "";
        if (motivo.Length < MinMotivo)
            return new RespuestaDto<ResultadoSolicitarRevocacionVbDto>(1,
                $"Indique el motivo de la revocación (mínimo {MinMotivo} caracteres).");
        if (motivo.Length > MaxMotivo)
            return new RespuestaDto<ResultadoSolicitarRevocacionVbDto>(1,
                $"El motivo no puede superar los {MaxMotivo} caracteres.");

        return await repositorio.SolicitarRevocacionVbAsync(idPropuesta, motivo, idUsuario, ct);
    }
}
