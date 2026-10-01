using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarSuministroCasoDeUso(ISuministrosRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarSuministroDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Clase))
            return new RespuestaDto<long>(1, "La clase es obligatoria.");

        if (string.IsNullOrWhiteSpace(dto.Tipo) || string.IsNullOrWhiteSpace(dto.Subtipo))
            return new RespuestaDto<long>(1, "El tipo y el subtipo son obligatorios.");

        if (string.IsNullOrWhiteSpace(dto.Unidad))
            return new RespuestaDto<long>(1, "La unidad es obligatoria.");

        if (string.IsNullOrWhiteSpace(dto.DescripcionAuto))
            return new RespuestaDto<long>(1, "La descripción es obligatoria.");

        bool esServicio = dto.Clase.Trim().Equals("servicio", StringComparison.OrdinalIgnoreCase);

        // Regla de negocio: equipos, pesas e instrumentos llevan marca y modelo; los servicios no.
        if (!esServicio && (string.IsNullOrWhiteSpace(dto.Marca) || string.IsNullOrWhiteSpace(dto.Modelo)))
            return new RespuestaDto<long>(1, "La marca y el modelo son obligatorios para esta clase.");

        if (dto.PrecioMinReferencia < 0 || (dto.Escalas ?? []).Any(e => e.Precio < 0))
            return new RespuestaDto<long>(1, "Los precios no pueden ser negativos.");

        dto.Clase = dto.Clase.Trim().ToLowerInvariant();

        return await repositorio.GuardarSuministroAsync(dto, idUsuario, ct);
    }
}
