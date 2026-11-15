using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Crea o edita una sede del cliente. Region = departamento del ubigeo (el nombre del campo se mantiene por compatibilidad con el front).
/// Ubicación (pin del mapa): opcional; si viene, las dos coordenadas y dentro del Perú. Al editar, sin coordenadas se conserva la guardada.
/// </summary>
public class GuardarSedeCasoDeUso(IMaestrosRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarSedeDto dto, string usuCre, CancellationToken ct = default)
    {
        var error = UbicacionPeru.Validar(dto.Latitud, dto.Longitud, obligatoria: false);
        if (error is not null)
            return new RespuestaDto<long>(1, error);
        return await repositorio.GuardarSedeAsync(dto, usuCre, ct);
    }
}
