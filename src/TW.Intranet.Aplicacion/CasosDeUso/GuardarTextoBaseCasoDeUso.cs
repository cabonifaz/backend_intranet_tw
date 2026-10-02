using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarTextoBaseCasoDeUso(ITextosBaseRepositorio repositorio)
{
    private static readonly string[] NivelesSangria = ["estandar", "primer_nivel", "segundo_nivel", "vineta"];

    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarTextoBaseDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.CodigoCorto))
            return new RespuestaDto<long>(1, "El código corto es obligatorio.");

        if (string.IsNullOrWhiteSpace(dto.TipoCategoria))
            return new RespuestaDto<long>(1, "La categoría es obligatoria.");

        if (string.IsNullOrWhiteSpace(dto.Nombre))
            return new RespuestaDto<long>(1, "El nombre / referencia clave es obligatorio.");

        if (string.IsNullOrWhiteSpace(dto.TextoClausula))
            return new RespuestaDto<long>(1, "El contenido del texto es obligatorio.");

        if (dto.OrdenAparicion < 1)
            return new RespuestaDto<long>(1, "El orden de aparición debe ser 1 o mayor.");

        if (!string.IsNullOrWhiteSpace(dto.NivelSangria) && !NivelesSangria.Contains(dto.NivelSangria))
            return new RespuestaDto<long>(1, "El nivel de sangría no es válido.");

        dto.CodigoCorto = dto.CodigoCorto.Trim().ToUpperInvariant();

        return await repositorio.GuardarTextoBaseAsync(dto, idUsuario, ct);
    }
}
