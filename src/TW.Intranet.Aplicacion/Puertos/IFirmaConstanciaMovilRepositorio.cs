using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>App Mobile HU-17 — Firma de informes y constancia de servicio (todo por procedimientos almacenados).</summary>
public interface IFirmaConstanciaMovilRepositorio
{
    Task<RespuestaDto<FirmasMovilDto>> ObtenerFirmasAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<ResumenFirmasMovilDto>> ObtenerResumenAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<ComparablesFirmaMovilDto>> ObtenerComparablesAsync(long idUsuario, long idOs, string clave, CancellationToken ct);
    Task<RespuestaDto<RegistroFirmaMovilDto>> GuardarFirmaAsync(long idUsuario, long idOs, string clave, string modo, string? trazos, string? hash, string? nombre, string? rutaFoto, string? motivo, CancellationToken ct);
    Task<RespuestaDto<ConstanciaMovilDto>> ObtenerConstanciaAsync(long idUsuario, long idOs, CancellationToken ct);
    Task<RespuestaDto<RegistroConstanciaMovilDto>> GuardarConstanciaAsync(long idUsuario, long idOs, string accion, string? trazos, string? hash, string? nombre, string? rutaFoto, CancellationToken ct);
    Task<RespuestaDto<CierreConstanciaMovilDto>> RegistrarCierreAsync(long idUsuario, long idOs, string? rutaPdf, string envioEstado, string? envioDestino, string? envioDetalle, CancellationToken ct);
    Task<RespuestaDto<string>> ObtenerRutaArchivoAsync(long idUsuario, long idOs, string tipo, CancellationToken ct);
}

/// <summary>Arma el PDF de la constancia de servicio (con las firmas dibujadas como vectores).</summary>
public interface IGeneradorConstanciaPdf
{
    byte[] Generar(DatosConstanciaPdf datos);
}
