namespace TW.Intranet.Aplicacion.Dtos;

// App Mobile HU-22 — Ingreso de equipos (OS)

/// <summary>Ingreso ya registrado de un equipo de la OS. <c>EstadoIngreso</c>: operativo · con_observaciones · inoperativo.</summary>
public record IngresoEquipoMovilDto(long IdOsEquipo, string EstadoIngreso, string? Observacion, string? IngresadoEn, int Fotos);

public record IngresosOsMovilDto(IReadOnlyList<IngresoEquipoMovilDto> Ingresos);

public record ResultadoIngresoEquipoMovilDto(long IdIngreso, long IdOsEquipo, string EstadoIngreso, string? IngresadoEn, int Fotos);
