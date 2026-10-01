namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Nivel de precio. Nivel: "estandar" | "volumen" | "corporativo_alto".</summary>
public record EscalaTarifaDto(string Nivel, decimal? Precio);
