using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IConsultaRucRepositorio
{
    /// <summary>Caché vigente (diasVigencia = 0 la ignora) y cliente ya registrado con ese RUC.</summary>
    Task<RespuestaDto<LecturaCacheRucDto>> ObtenerAsync(string ruc, int diasVigencia, CancellationToken ct);

    Task<RespuestaDto<object>> GuardarAsync(DatosRucProveedorDto datos, string proveedor, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<object>> RegistrarLogAsync(
        string ruc, string proveedor, string resultado, int? codigoHttp, string? detalle,
        int duracionMs, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<UsoConsultaRucDto>> ObtenerUsoAsync(int meses, CancellationToken ct);
}
