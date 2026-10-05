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

        if (string.IsNullOrWhiteSpace(dto.DescripcionAuto))
            return new RespuestaDto<long>(1, "La descripción es obligatoria.");

        // Reunión 02-oct: marca y modelo son opcionales (si no tiene, "Genérico" o vacío);
        // en servicios el SP los deja vacíos junto con procedencia y alcance.

        if (dto.PrecioMinReferencia < 0 || (dto.Escalas ?? []).Any(e => e.Precio < 0))
            return new RespuestaDto<long>(1, "Los precios no pueden ser negativos.");

        dto.Clase = dto.Clase.Trim().ToLowerInvariant();

        return await repositorio.GuardarSuministroAsync(dto, idUsuario, ct);
    }
}
