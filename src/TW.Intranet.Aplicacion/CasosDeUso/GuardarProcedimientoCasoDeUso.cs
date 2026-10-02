using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarProcedimientoCasoDeUso(IProcedimientosRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarProcedimientoDto dto, long idUsuario, string? pcRegistro, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Codigo))
            return new RespuestaDto<long>(1, "El código técnico es obligatorio.");

        if (dto.Anio < 1950 || dto.Anio > DateTime.Today.Year + 1)
            return new RespuestaDto<long>(1, "El año de edición no es válido.");

        if (dto.Version < 1)
            return new RespuestaDto<long>(1, "La versión debe ser 1 o mayor.");

        if (string.IsNullOrWhiteSpace(dto.AutorNorma))
            return new RespuestaDto<long>(1, "El autor / organismo emisor es obligatorio.");

        if (string.IsNullOrWhiteSpace(dto.Descripcion))
            return new RespuestaDto<long>(1, "La descripción es obligatoria.");

        dto.Codigo = dto.Codigo.Trim().ToUpperInvariant();

        return await repositorio.GuardarProcedimientoAsync(dto, idUsuario, pcRegistro, ct);
    }
}
