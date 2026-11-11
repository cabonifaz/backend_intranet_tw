using System.Text.RegularExpressions;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-14 / HU-34 — Correlativos de Metrología ──────────────────────────────────────────────────────────
// Las reglas (Hard Stop, ensayos finalizados, un solo ticket abierto por equipo, secuencia única CC-####-AAAA, reserva diaria, permisos del área de Metrología,
// notificaciones y auditoría) viven en los procedimientos. Aquí solo se valida la entrada.

/// <summary>Validación de la entrada de Correlativos (pública y sin dependencias: se prueba sin base de datos).</summary>
public static partial class ValidacionCorrelativos
{
    public const int MaxObservacion = 300;
    public static readonly string[] Filtros = ["todos", "pendientes", "asignados"];
    public static readonly string[] ModosReserva = ["todos", "propia"];

    [GeneratedRegex(@"^CC-[0-9]{4}-[0-9]{4}$")]
    private static partial Regex PatronCorrelativo();

    /// <summary>Filtro de "Mis tickets": vacío = todos; otro valor distinto de los permitidos → null.</summary>
    public static string? NormalizarFiltro(string? filtro)
    {
        var f = string.IsNullOrWhiteSpace(filtro) ? "todos" : filtro.Trim().ToLowerInvariant();
        return Filtros.Contains(f) ? f : null;
    }

    /// <summary>Correlativo con el formato CC-####-AAAA en mayúsculas; vacío → (true, null); formato incorrecto → (false, null).</summary>
    public static (bool Valido, string? Codigo) NormalizarCorrelativo(string? texto)
    {
        var t = texto?.Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(t)) return (true, null);
        return PatronCorrelativo().IsMatch(t) ? (true, t) : (false, null);
    }

    public static string? ErrorSolicitud(SolicitarCorrelativoDto? d)
    {
        if (d?.IdTipoCertificado is null or <= 0) return "Elige el tipo de certificado.";
        if ((d.Observacion?.Trim().Length ?? 0) > MaxObservacion) return $"La observación puede tener hasta {MaxObservacion} caracteres.";
        return null;
    }
}

/// <summary>Lado del técnico (HU-14): datos de la solicitud, solicitar, mis tickets, guardar el certificado y su reserva diaria.</summary>
public class CorrelativosTecnicoMovilCasoDeUso(ICorrelativosMovilRepositorio repositorio)
{
    private const string SinUsuario = "No se pudo identificar al usuario.";
    private const string SinEquipo = "Servicio o equipo no válido.";

    public Task<RespuestaDto<SolicitudCorrelativoDto>> ObtenerSolicitudAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<SolicitudCorrelativoDto>(1, SinUsuario))
        : idOs <= 0 || idOsEquipo <= 0 ? Task.FromResult(new RespuestaDto<SolicitudCorrelativoDto>(1, SinEquipo))
        : repositorio.ObtenerSolicitudAsync(idUsuario, idOs, idOsEquipo, ct);

    public Task<RespuestaDto<TicketCreadoDto>> SolicitarAsync(long idUsuario, long idOs, long idOsEquipo, SolicitarCorrelativoDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<TicketCreadoDto>(1, SinUsuario));
        if (idOs <= 0 || idOsEquipo <= 0) return Task.FromResult(new RespuestaDto<TicketCreadoDto>(1, SinEquipo));
        var error = ValidacionCorrelativos.ErrorSolicitud(d);
        if (error is not null) return Task.FromResult(new RespuestaDto<TicketCreadoDto>(1, error));
        var obs = string.IsNullOrWhiteSpace(d!.Observacion) ? null : d.Observacion.Trim();
        return repositorio.SolicitarAsync(idUsuario, idOs, idOsEquipo, d.IdTipoCertificado!.Value, obs, ct);
    }

    public Task<RespuestaDto<IReadOnlyList<TicketCorrelativoDto>>> ObtenerTicketsAsync(long idUsuario, string? filtro, long? idOs, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<IReadOnlyList<TicketCorrelativoDto>>(1, SinUsuario));
        var f = ValidacionCorrelativos.NormalizarFiltro(filtro);
        return f is null
            ? Task.FromResult(new RespuestaDto<IReadOnlyList<TicketCorrelativoDto>>(1, "El filtro de tickets no es válido."))
            : repositorio.ObtenerTicketsAsync(idUsuario, f, idOs is > 0 ? idOs : null, ct);
    }

    public Task<RespuestaDto<CertificadoGuardadoDto>> GuardarCertificadoAsync(long idUsuario, long idOs, long idOsEquipo, GuardarCertificadoDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<CertificadoGuardadoDto>(1, SinUsuario));
        if (idOs <= 0 || idOsEquipo <= 0) return Task.FromResult(new RespuestaDto<CertificadoGuardadoDto>(1, SinEquipo));
        var (valido, codigo) = ValidacionCorrelativos.NormalizarCorrelativo(d?.NumeroCertificado);
        return !valido || codigo is null
            ? Task.FromResult(new RespuestaDto<CertificadoGuardadoDto>(1, "El certificado debe ser el correlativo que asignó Metrología, con el formato CC-0000-2026."))
            : repositorio.GuardarCertificadoAsync(idUsuario, idOs, idOsEquipo, codigo, ct);
    }

    /// <summary>La reserva diaria del propio técnico de Metrología (idempotente; quien no es técnico de Metrología no recibe nada).</summary>
    public Task<RespuestaDto<ReservaGeneradaDto>> GenerarMiReservaAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<ReservaGeneradaDto>(1, SinUsuario)) : repositorio.GenerarReservaAsync(idUsuario, "propia", ct);
}

/// <summary>Lado del Jefe de Metrología (HU-34): solicitudes de los técnicos, asignar el correlativo y generar la reserva diaria.</summary>
public class CorrelativosJefaturaMovilCasoDeUso(ICorrelativosMovilRepositorio repositorio)
{
    private const string SinUsuario = "No se pudo identificar al usuario.";

    public Task<RespuestaDto<CorrelativosJefaturaDto>> ObtenerPanelAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<CorrelativosJefaturaDto>(1, SinUsuario)) : repositorio.ObtenerPanelJefaturaAsync(idUsuario, ct);

    public Task<RespuestaDto<AsignacionCorrelativoDto>> AsignarAsync(long idUsuario, long idTicket, AsignarCorrelativoDto? d, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<AsignacionCorrelativoDto>(1, SinUsuario));
        if (idTicket <= 0) return Task.FromResult(new RespuestaDto<AsignacionCorrelativoDto>(1, "Ticket no encontrado."));
        var (valido, codigo) = ValidacionCorrelativos.NormalizarCorrelativo(d?.Correlativo);
        return !valido
            ? Task.FromResult(new RespuestaDto<AsignacionCorrelativoDto>(1, "El correlativo debe tener el formato CC-0000-2026."))
            : repositorio.AsignarAsync(idUsuario, idTicket, codigo, ct);
    }

    /// <summary>La reserva de TODOS los técnicos de Metrología (la dispara el jefe al abrir la pantalla; idempotente por día).</summary>
    public Task<RespuestaDto<ReservaGeneradaDto>> GenerarReservaAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<ReservaGeneradaDto>(1, SinUsuario)) : repositorio.GenerarReservaAsync(idUsuario, "todos", ct);
}
