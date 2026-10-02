using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class ObtenerDatosNuevaPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    public Task<RespuestaDto<DatosNuevaPropuestaDto>> EjecutarAsync(long idRequerimiento, CancellationToken ct = default)
        => idRequerimiento <= 0
            ? Task.FromResult(new RespuestaDto<DatosNuevaPropuestaDto>(1, "Indique el requerimiento de origen."))
            : repositorio.ObtenerDatosNuevaPropuestaAsync(idRequerimiento, ct);
}
