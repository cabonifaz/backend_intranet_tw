using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>Procedimientos activos para el combo de Suministros clase Servicio (HU-86).</summary>
public class ObtenerProcedimientosOpcionesCasoDeUso(IProcedimientosRepositorio repositorio)
{
    public Task<RespuestaDto<List<OpcionCatalogoDto>>> EjecutarAsync(CancellationToken ct = default)
        => repositorio.ObtenerOpcionesAsync(ct);
}
