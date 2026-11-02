using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class AdjuntosRequerimientoRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IAdjuntosRequerimientoRepositorio
{
    public Task<RespuestaDto<long>> RegistrarAsync(long idRequerimiento, string nombreArchivo, string ruta, string tipoContenido,
                                                   long tamanoBytes, long idUsuario, bool soloValidar, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarAdjuntoRequerimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_requerimiento", idRequerimiento);
                p.AddWithValue("p_nombre_archivo",   nombreArchivo);
                p.AddWithValue("p_ruta",             ruta);
                p.AddWithValue("p_tipo_contenido",   tipoContenido);
                p.AddWithValue("p_tamano_bytes",     tamanoBytes);
                p.AddWithValue("p_solo_validar",     Bit(soloValidar));
            },
            async (r, mensaje) =>
            {
                if (soloValidar) return new RespuestaDto<long>(2, mensaje, 0);
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_documento") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            },
            ct);

    public Task<RespuestaDto<RutaAdjuntoRequerimientoDto>> ObtenerAsync(long idDocumento, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAdjuntoRequerimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_documento", idDocumento);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RutaAdjuntoRequerimientoDto>(1, "El adjunto no existe.");
                return new RespuestaDto<RutaAdjuntoRequerimientoDto>(2, mensaje, new RutaAdjuntoRequerimientoDto(
                    Texto(r, "ruta") ?? "", Texto(r, "nombre_archivo") ?? "adjunto",
                    Texto(r, "tipo_contenido") ?? "application/octet-stream"));
            },
            ct);

    public Task<RespuestaDto<bool>> EliminarAsync(long idDocumento, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_EliminarAdjuntoRequerimiento",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_documento", idDocumento);
            },
            (r, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)),
            ct);
}
