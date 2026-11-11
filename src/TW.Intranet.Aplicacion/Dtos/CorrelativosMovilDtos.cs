namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-14 (Técnico) y HU-34 (Jefe de Metrología) — Correlativos de certificación ───────────────────────
// Fechas con hora de Lima y sin zona (como el resto del móvil). Los números TK-MET-##### y CC-####-AAAA los arma el back; la app solo los muestra.

// ---------- Técnico: solicitud, tickets y certificado ----------

public record TipoCertificadoDto(int IdTipo, string Nombre);

/// <summary>El correlativo que Metrología asignó al equipo y que el técnico aún no usó (modal "Correlativo y certificado").</summary>
public record CorrelativoAsignadoDto(long IdTicket, string Ticket, string Correlativo, DateTime? AsignadoEn, string? AsignadoPor);

public record CabeceraSolicitudCorrelativoDto(
    long IdOs, string NumeroOs, long IdOsEquipo, string Equipo, int Numero, string? NumeroSerie, string? CodigoCliente, string? CodigoTw, string? Clase, string? Capacidad,
    // OS (servicio técnico) u OM (metrología) según la RQ.
    string TipoOrden, string? NumeroRq,
    // Conforme / No conforme (ensayos de la HU-10); null si aún no se finalizaron.
    string? Resultado,
    bool PuedeSolicitar, string? MotivoBloqueo,
    long? TicketAbiertoId, string? TicketAbiertoNumero, string? TicketAbiertoEstado,
    // El certificado que ya forma parte del informe del equipo (etapa 5 conforme).
    string? NumeroCertificado,
    // El técnico es de Metrología: recibe la reserva diaria de correlativos.
    bool TecnicoMetrologia);

public record SolicitudCorrelativoDto(
    CabeceraSolicitudCorrelativoDto Cabecera, IReadOnlyList<TipoCertificadoDto> Tipos, CorrelativoAsignadoDto? Asignado, IReadOnlyList<string> ReservaLibre);

/// <summary>Cuerpo de "Solicitar correlativo".</summary>
public class SolicitarCorrelativoDto
{
    public int? IdTipoCertificado { get; set; }
    public string? Observacion { get; set; }
}

public record TicketCreadoDto(long IdTicket, string Numero, string Estado, DateTime? SolicitadoEn, int Notificados);

public record TicketCorrelativoDto(
    long IdTicket, string Numero,
    // solicitado (Pendiente) · asignado · despachado (asignado y ya usado en el certificado).
    string Estado, bool Usado,
    long IdOs, string NumeroOs, long? IdOsEquipo, string? Equipo, string? CodigoEquipo, string? NumeroSerie,
    int? IdTipo, string? TipoCertificado, string? Observacion,
    DateTime? SolicitadoEn, string? Solicitante,
    string? Correlativo, DateTime? AsignadoEn, string? AsignadoPor,
    bool PuedeUsar);

/// <summary>Cuerpo de "Guardar" del modal Correlativo y certificado.</summary>
public class GuardarCertificadoDto
{
    public string? NumeroCertificado { get; set; }
}

public record CertificadoGuardadoDto(string NumeroCertificado, string? Origen, string? Ticket);

public record ReservaGeneradaDto(int Generados, int Tecnicos);

// ---------- Jefe de Metrología ----------

public record KpisCorrelativosDto(int Pendientes, int AsignadosHoy, int Reservados, string? SiguienteSugerido, int ReservaDiaria);

public record TicketJefaturaDto(
    long IdTicket, string Numero, string Estado, string? Tecnico, string NumeroOs, string? Equipo, string? CodigoEquipo, string? Capacidad,
    string? TipoCertificado, string? Observacion, string? Patron, string? Resultado, DateTime? SolicitadoEn, int Minutos,
    string? Correlativo, DateTime? AsignadoEn, string? AsignadoPor);

public record ReservaTecnicoDto(long IdUsuario, string Tecnico, int Libres, string CodigosLibres, int Usados, string UsadosTexto);

public record CorrelativosJefaturaDto(KpisCorrelativosDto Kpis, IReadOnlyList<TicketJefaturaDto> Tickets, IReadOnlyList<ReservaTecnicoDto> Reserva);

/// <summary>Cuerpo de "Asignar correlativo": vacío = el siguiente sugerido.</summary>
public class AsignarCorrelativoDto
{
    public string? Correlativo { get; set; }
}

public record AsignacionCorrelativoDto(
    long IdTicket, string Numero, string Estado, string Correlativo, DateTime? AsignadoEn, string? AsignadoPor, string? Tecnico, string? SiguienteSugerido);
