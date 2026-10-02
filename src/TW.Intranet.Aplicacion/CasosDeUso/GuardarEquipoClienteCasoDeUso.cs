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

        if (string.IsNullOrWhiteSpace(dto.Marca) || string.IsNullOrWhiteSpace(dto.Modelo))
            return new RespuestaDto<long>(1, "La marca y el modelo son obligatorios.");

        return await repositorio.GuardarEquipoAsync(dto, idUsuario, ct);
    }
}
