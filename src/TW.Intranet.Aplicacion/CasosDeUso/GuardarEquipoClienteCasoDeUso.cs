using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarEquipoClienteCasoDeUso(IEquiposClienteRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarEquipoClienteDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.NumSerie))
            return new RespuestaDto<long>(1, "El número de serie es obligatorio.");

        if (dto.IdCliente == 0 || dto.IdSede == 0)
            return new RespuestaDto<long>(1, "Cliente y sede son obligatorios.");

        if (string.IsNullOrWhiteSpace(dto.Clasificacion))
            return new RespuestaDto<long>(1, "La clasificación es obligatoria.");

        // Marca y modelo ya no se piden (reunión 02-oct): el SP los toma del suministro.
        if (dto.IdEquipo == 0 && (dto.IdSuministro ?? 0) == 0
            && (string.IsNullOrWhiteSpace(dto.Marca) || string.IsNullOrWhiteSpace(dto.Modelo)))
            return new RespuestaDto<long>(1, "Seleccione el suministro del equipo.");

        if (string.Equals(dto.ClaseExactitud?.Trim(), "IIII", StringComparison.OrdinalIgnoreCase))
            dto.ClaseExactitud = "IV";

        dto.Clasificacion = dto.Clasificacion.Trim().ToLowerInvariant();
        if (dto.Clasificacion is not ("equipo" or "instrumento" or "pesa"))
            return new RespuestaDto<long>(1, "La clasificación técnica debe ser Equipo, Instrumento o Pesa.");

        return await repositorio.GuardarEquipoAsync(dto, idUsuario, ct);
    }
}
