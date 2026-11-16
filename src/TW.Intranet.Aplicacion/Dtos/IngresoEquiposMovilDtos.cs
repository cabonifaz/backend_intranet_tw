namespace TW.Intranet.Aplicacion.Dtos;

// App Mobile HU-22 — Ingreso de equipos (OS)

/// <summary>Ingreso ya registrado de un equipo de la OS. <c>EstadoIngreso</c>: operativo · con_observaciones · inoperativo.</summary>
public record IngresoEquipoMovilDto(long IdOsEquipo, string EstadoIngreso, string? Observacion, string? IngresadoEn, int Fotos);

public record IngresosOsMovilDto(IReadOnlyList<IngresoEquipoMovilDto> Ingresos);

/// <summary>Equipo ya registrado que se agregó a la lista de la OS al escanear su QR.</summary>
public record EquipoAgregadoMovilDto(
    long IdOsEquipo, long IdEquipo, string CodigoTw,
    string? Marca = null, string? Modelo = null, string? NumSerie = null, string? CodigoCliente = null, string? Ubicacion = null);

public record ResultadoIngresoEquipoMovilDto(long IdIngreso, long IdOsEquipo, string EstadoIngreso, string? IngresadoEn, int Fotos);
