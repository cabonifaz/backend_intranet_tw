namespace TW.Intranet.Infraestructura.Configuracion;

/// <summary>
/// Wrapper de la cadena de conexión MySQL registrado como singleton en DI.
/// Los adaptadores de infraestructura lo reciben por constructor.
/// </summary>
public record CadenaConexionBd(string Valor);
