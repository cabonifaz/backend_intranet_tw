namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// Sobre de respuesta que refleja el contrato de todos los stored procedures:
/// IdTipoMensaje 1 = regla de negocio, 2 = éxito, 3 = error de sistema.
/// </summary>
public record RespuestaDto<T>(int IdTipoMensaje, string Mensaje, T? Datos = default);
