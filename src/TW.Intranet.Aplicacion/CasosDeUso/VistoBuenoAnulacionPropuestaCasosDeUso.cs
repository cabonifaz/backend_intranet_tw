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
