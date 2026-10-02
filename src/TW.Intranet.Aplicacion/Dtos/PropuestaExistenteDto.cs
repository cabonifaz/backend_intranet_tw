namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Última propuesta vinculada al RQ (para el aviso "Crear nueva versión").</summary>
public record PropuestaExistenteDto(long IdPropuesta, string Numero, int Version, string Estado);
