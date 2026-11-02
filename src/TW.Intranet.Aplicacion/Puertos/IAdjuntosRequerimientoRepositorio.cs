using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IAdjuntosRequerimientoRepositorio
{
    /// <summary>soloValidar = true: valida permisos/estado/límite antes de guardar el archivo. Devuelve el id_documento.</summary>
    Task<RespuestaDto<long>> RegistrarAsync(long idRequerimiento, string nombreArchivo, string ruta, string tipoContenido,
                                            long tamanoBytes, long idUsuario, bool soloValidar, CancellationToken ct);
    Task<RespuestaDto<RutaAdjuntoRequerimientoDto>> ObtenerAsync(long idDocumento, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<bool>> EliminarAsync(long idDocumento, long idUsuario, CancellationToken ct);
}
