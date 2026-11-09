namespace TW.Intranet.Aplicacion.Dtos;

// ── App Mobile HU-06 — Registro de llegada y Hard Stop ─────────────────────────────────────────

/// <summary>Coordenada de la planta del cliente y radio dentro del cual se puede confirmar la llegada.</summary>
public record ReferenciaGpsMovilDto(decimal Latitud, decimal Longitud, int RadioMetros);

/// <summary>La llegada ya registrada en este viaje. Resultado: valida | sin_referencia (la planta no tenía coordenada).</summary>
public record LlegadaRegistradaMovilDto(
    DateTime? En, decimal? Latitud, decimal? Longitud, decimal? PrecisionMetros, int? DistanciaMetros, string? Resultado);

/// <summary>
/// Contexto de la pantalla "Registrar llegada". Las horas son de Lima. Referencia null = la planta no tiene coordenada registrada.
/// PuedeRegistrar = OS en ruta y sin llegada en este viaje; MotivoNoRegistra dice por qué no (cuando no se puede).
/// </summary>
public record LlegadaMovilDto(
    long IdOs, string NumeroOs, string EstadoOs, string? Cliente, string? Sede, string? Direccion, string? HoraProgramada,
    ReferenciaGpsMovilDto? Referencia, DateTime? SalidaEn, LlegadaRegistradaMovilDto? Llegada, bool PuedeRegistrar,
    int PrecisionMaximaMetros, string? MotivoNoRegistra);

/// <summary>
/// Lo que la app envía para validar o registrar la llegada. CapturadoEn = hora (ISO 8601, UTC) en que el técnico confirmó en el teléfono:
/// si no había conexión y la app la guardó para enviarla después, el SP respeta esa hora (no futura, máx. 24 h).
/// </summary>
public class PeticionLlegadaMovilDto
{
    public decimal? Latitud         { get; set; }
    public decimal? Longitud        { get; set; }
    public decimal? PrecisionMetros { get; set; }
    public string?  CapturadoEn     { get; set; }
}

/// <summary>
/// Comparación de la ubicación con la planta (no registra). Resultado: valida | fuera_rango | sin_referencia | precision_baja.
/// Registrable = se puede confirmar la llegada con esa ubicación.
/// </summary>
public record ValidacionLlegadaMovilDto(
    string Resultado, bool Registrable, int? DistanciaMetros, int? RadioMetros, decimal PrecisionMetros, string Mensaje);

/// <summary>Llegada registrada. YaRegistrada = el envío ya existía (reintento): no se duplicó. Diferida = se guardó sin conexión y llegó después.</summary>
public record ResultadoLlegadaMovilDto(
    long IdEvento, DateTime? LlegadaEn, int? DistanciaMetros, decimal? PrecisionMetros, string Resultado, bool YaRegistrada, bool Diferida);
