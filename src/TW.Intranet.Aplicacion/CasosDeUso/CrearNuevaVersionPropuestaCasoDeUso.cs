using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// HU-10 — Crear nueva versión. Validaciones de forma aquí; las de negocio
/// (última versión, estado, borrador existente, motivo válido) están en el SP.
/// </summary>
public class CrearNuevaVersionPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    private const int MaxDescripcion = 500;

    public async Task<RespuestaDto<NuevaVersionPropuestaResultadoDto>> EjecutarAsync(
        long idPropuestaOrigen, CrearNuevaVersionPropuestaDto dto, long idUsuario, CancellationToken ct = default)
    {
        string? error = Validar(idPropuestaOrigen, dto);
        if (error is not null)
            return new RespuestaDto<NuevaVersionPropuestaResultadoDto>(1, error);

        return await repositorio.CrearNuevaVersionAsync(idPropuestaOrigen, dto, idUsuario, ct);
    }

    private static string? Validar(long idPropuestaOrigen, CrearNuevaVersionPropuestaDto dto)
    {
        if (idPropuestaOrigen <= 0)
            return "Indique la propuesta a versionar.";

        if (dto.IdMotivoNuevaVersion <= 0)
            return "Seleccione el motivo de la nueva versión.";

        var descripcion = dto.DescripcionCambios?.Trim() ?? "";
        if (descripcion.Length == 0)
            return "Describa brevemente los cambios de la nueva versión.";
        if (descripcion.Length > MaxDescripcion)
            return $"La descripción de los cambios no puede superar los {MaxDescripcion} caracteres.";

        dto.Copiar ??= new BloquesCopiaVersionDto();
        return null;
    }
}
