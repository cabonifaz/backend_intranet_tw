using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-22 — Órdenes de compra recibidas del cliente.</summary>
public interface IOrdenCompraRepositorio
{
    Task<RespuestaDto<PreparacionOrdenCompraDto>> PrepararAsync(long idPropuesta, long idUsuario, CancellationToken ct);

    /// <summary>Valida todo y devuelve la cobertura sin guardar (el PDF no es obligatorio en este modo).</summary>
    Task<RespuestaDto<CoberturaOrdenCompraDto>> ValidarAsync(long idPropuesta, DatosOrdenCompraDto datos, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<OrdenCompraRegistradaDto>> RegistrarAsync(long idPropuesta, ComandoOrdenCompra comando, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<RutaPdfOrdenCompraDto>> ObtenerRutaPdfAsync(long idOc, long idUsuario, CancellationToken ct);
}
