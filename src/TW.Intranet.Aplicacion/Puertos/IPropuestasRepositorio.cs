using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

public interface IPropuestasRepositorio
{
    Task<RespuestaDto<DatosNuevaPropuestaDto>> ObtenerDatosNuevaPropuestaAsync(
        long idRequerimiento, CancellationToken ct);

    Task<RespuestaDto<PropuestasPaginadoDto>> ObtenerPropuestasAsync(
        FiltrosPropuestasDto filtros, CancellationToken ct);

    Task<RespuestaDto<KpisPropuestasDto>> ObtenerKpisAsync(
        int? anio, long? idComercial, CancellationToken ct);

    Task<RespuestaDto<PropuestaDetalleDto>> ObtenerPropuestaPorIdAsync(
        long idPropuesta, CancellationToken ct);

    /// <summary>HU-09 — Workflow, SLA, documentos, versiones y actividad del detalle.</summary>
    Task<RespuestaDto<PropuestaContextoDto>> ObtenerContextoPropuestaAsync(
        long idPropuesta, CancellationToken ct);

    /// <summary>HU-10 — Crea la siguiente versión (borrador) copiando los bloques elegidos.</summary>
    Task<RespuestaDto<NuevaVersionPropuestaResultadoDto>> CrearNuevaVersionAsync(
        long idPropuestaOrigen, CrearNuevaVersionPropuestaDto dto, long idUsuario, CancellationToken ct);

    /// <summary>HU-11 — Aplica, previsualiza o quita el descuento global (tipo: porcentaje | monto | ninguno).</summary>
    Task<RespuestaDto<DescuentoPropuestaResultadoDto>> AplicarDescuentoAsync(
        long idPropuesta, string tipo, decimal valor, int? idMotivo, bool soloPrevisualizar,
        long idUsuario, CancellationToken ct);

    /// <summary>HU-12 — Prepara (soloPreparar) o realiza el envío a visto bueno.</summary>
    Task<RespuestaDto<VistoBuenoPropuestaDto>> EnviarVistoBuenoAsync(
        long idPropuesta, string? comentario, bool soloPreparar, long idUsuario, CancellationToken ct);

    /// <summary>HU-12 — Prepara (soloPreparar) o realiza la anulación.</summary>
    Task<RespuestaDto<AnulacionPropuestaDto>> AnularPropuestaAsync(
        long idPropuesta, int? idMotivo, string? justificacion, bool confirmacion, bool soloPreparar,
        long idUsuario, CancellationToken ct);

    Task<RespuestaDto<GuardarPropuestaResultadoDto>> GuardarPropuestaAsync(
        GuardarPropuestaDto dto, long idUsuario, CancellationToken ct);
}
