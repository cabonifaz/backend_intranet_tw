namespace TW.Intranet.Aplicacion.Dtos;

// App Mobile HU-20 — Reloj marcador de jornada.

/// <summary>Una marcación del día. Tipo: inicio_labores · inicio_refrigerio · fin_refrigerio · salida_planta · fin_labores. Puntualidad (solo el ingreso): a_tiempo | tardanza.</summary>
public record MarcacionJornadaDto(
    string Tipo, string Hora, string MarcadoUtc, string? Lugar, decimal? Latitud, decimal? Longitud, int? PrecisionM,
    string? Puntualidad, int? MinutosDiferencia, bool SinConexion);

/// <summary>Resumen de la jornada finalizada.</summary>
public record ResumenJornadaDto(int TrabajadoMin, int RefrigerioMin, string? Ingreso, int? MinutosTardanza);

/// <summary>La jornada de hoy (hora de Lima). Estado: sin_iniciar · en_labores · en_refrigerio · salio_planta · finalizada. Siguiente = el único paso habilitado (null si terminó).</summary>
public record JornadaMovilDto(
    string Fecha, string AhoraUtc, string Estado, string? Siguiente, string InicioProgramado, string FinProgramado, int ToleranciaMin, int RefrigerioMaxMin,
    IReadOnlyList<MarcacionJornadaDto> Marcaciones, ResumenJornadaDto? Resumen);

/// <summary>Lo que envía la app al marcar. MarcadoEn: hora (ISO 8601, UTC) en que el teléfono tomó la marcación; SinConexion: se guardó en el teléfono y se envió después.</summary>
public class MarcarJornadaDto
{
    public string?  Tipo            { get; set; }
    public decimal? Latitud         { get; set; }
    public decimal? Longitud        { get; set; }
    public decimal? PrecisionMetros { get; set; }
    public string?  MarcadoEn       { get; set; }
    public bool     SinConexion     { get; set; }
}

public record MarcacionRegistradaDto(
    string Tipo, bool Repetida, string Estado, string? Siguiente, string? Hora, string? Lugar, string? Puntualidad, int? MinutosDiferencia);
