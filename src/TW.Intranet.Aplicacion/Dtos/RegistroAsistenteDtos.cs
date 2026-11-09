namespace TW.Intranet.Aplicacion.Dtos;

// ── HU-53 Registro operativo del Asistente de Seguimiento (Sprint 5) ──────────────────────────────────

/// <summary>Cuerpo del POST. Los campos que no corresponden al modo elegido se ignoran (el caso de uso los descarta).</summary>
public record RegistrarAsistenteSolicitudDto(
    string? Modo, string? Descripcion, string? Fuente, string? Vinculo,
    int? IdTipo, int? DuracionMin, string? Impacto, string? EvidenciaUrl,
    string? NuevoEstado, int? IdMotivo, string? Comentario);

/// <summary>Datos ya validados y limpios que viajan al SP.</summary>
public record RegistroAsistenteNormalizado(
    string Modo, string? Descripcion, string? Fuente, string? Vinculo,
    int? IdTipo, int? DuracionMin, string? Impacto, string? EvidenciaUrl,
    string? NuevoEstado, int? IdMotivo, string? Comentario);

public record RegistroAsistenteCreadoDto(long IdRegistro, string Modo, int Notificados, string? EstadoNuevo);

public record ContextoRegistroAsistenteDto(
    string RegistrandoComo, string HoraActual, string Numero, string? Tecnico, string EstadoActual, int NivelActual, bool PuedeRegistrar, string? MensajeBloqueo = null);
public record OpcionRegistroAsistenteDto(int Id, string Nombre, string Codigo);
public record EstadoRegistroAsistenteDto(string Codigo, string Nombre, int Nivel, bool Permitido);
public record EventoVinculableDto(string Clave, string Hora, string Titulo);
public record MiRegistroAsistenteDto(long IdRegistro, string Modo, string Hora, string Texto, string? Fuente, string Badge, int HaceMin);

public record FormularioRegistroAsistenteDto(
    ContextoRegistroAsistenteDto Contexto,
    IReadOnlyList<OpcionRegistroAsistenteDto> TiposDemora,
    IReadOnlyList<OpcionRegistroAsistenteDto> Motivos,
    IReadOnlyList<EstadoRegistroAsistenteDto> Estados,
    IReadOnlyList<EventoVinculableDto> EventosVinculables,
    IReadOnlyList<MiRegistroAsistenteDto> MisRegistros);
