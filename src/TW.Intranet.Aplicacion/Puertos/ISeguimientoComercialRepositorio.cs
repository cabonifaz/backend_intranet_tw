using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>HU-17 / HU-18 / HU-19 / HU-20 / HU-21 — Seguimiento comercial de propuestas enviadas.</summary>
public interface ISeguimientoComercialRepositorio
{
    Task<RespuestaDto<BandejaSeguimientoDto>> ObtenerBandejaAsync(FiltrosBandejaSeguimientoDto f, long idUsuario, CancellationToken ct);
    Task<RespuestaDto<DetalleSeguimientoDto>> ObtenerDetalleAsync(long idPropuesta, long idUsuario, CancellationToken ct);

    // HU-19
    Task<RespuestaDto<PreparacionRegistroSeguimientoDto>> PrepararRegistroAsync(long idPropuesta, long idUsuario, CancellationToken ct);

    /// <summary>soloValidar = true: valida todo sin guardar (Datos = 0).</summary>
    Task<RespuestaDto<long>> RegistrarAsync(long idPropuesta, ComandoRegistroSeguimiento comando, long idUsuario,
                                            bool soloValidar, CancellationToken ct);

    /// <summary>estado: borrador | error.</summary>
    Task<RespuestaDto<CorreoSeguimientoGuardadoDto>> GuardarCorreoAsync(long idPropuesta, ComandoCorreoSeguimiento comando,
                                            string estado, string? proveedor, string? error, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<long>> RegistrarAdjuntoAsync(long idSeguimiento, string nombreArchivo, string ruta, string tipoContenido,
                                            long tamanoBytes, long idUsuario, bool soloValidar, CancellationToken ct);

    Task<RespuestaDto<RutaAdjuntoSeguimientoDto>> ObtenerAdjuntoAsync(long idAdjunto, long idUsuario, CancellationToken ct);

    // HU-20
    Task<RespuestaDto<PreparacionReprogramacionDto>> PrepararReprogramacionAsync(long idPropuesta, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<long>> ReprogramarAccionAsync(long idPropuesta, ReprogramarAccionDto dto, long idUsuario, CancellationToken ct);

    // HU-21
    Task<RespuestaDto<PreparacionCierreSeguimientoDto>> PrepararCierreAsync(long idPropuesta, long idUsuario, CancellationToken ct);

    Task<RespuestaDto<ResultadoCierreSeguimientoDto>> CerrarAsync(long idPropuesta, ComandoCierreSeguimiento comando, long idUsuario,
                                                                bool soloValidar, CancellationToken ct);

    // Observaciones 2026-10-15 — recordatorios de las acciones (worker)
    Task<RespuestaDto<ResultadoRecordatoriosSeguimientoDto>> ProcesarRecordatoriosAsync(int limite, CancellationToken ct);
}
