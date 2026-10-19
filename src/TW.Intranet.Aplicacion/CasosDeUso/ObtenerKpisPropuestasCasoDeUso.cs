using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>HU-08 — Tarjetas resumen de la bandeja de propuestas.</summary>
public class ObtenerKpisPropuestasCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<KpisPropuestasDto>> EjecutarAsync(int? anio, long? idComercial, CancellationToken ct = default)
        => repositorio.ObtenerKpisAsync(anio, idComercial, ct);
}
