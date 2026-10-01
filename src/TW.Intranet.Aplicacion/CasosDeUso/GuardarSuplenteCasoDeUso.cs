using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarSuplenteCasoDeUso(IUsuariosRepositorio repositorio)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarSuplenteDto dto, string usuario, CancellationToken ct = default)
    {
        if (dto.IdTitular <= 0 || dto.IdSuplente <= 0)
            return new RespuestaDto<long>(1, "Debe indicar el titular y el suplente.");

        if (dto.IdTitular == dto.IdSuplente)
            return new RespuestaDto<long>(1, "El titular y el suplente no pueden ser la misma persona.");

        if (!TryFecha(dto.FechaInicio, out var fechaInicio))
            return new RespuestaDto<long>(1, "La fecha de inicio es obligatoria y debe ser válida.");

        DateTime? fechaFin = null;
        if (!dto.SinFechaFin && !string.IsNullOrWhiteSpace(dto.FechaFin))
        {
            if (!TryFecha(dto.FechaFin, out var fin))
                return new RespuestaDto<long>(1, "La fecha de fin no es válida.");
            if (fin < fechaInicio)
                return new RespuestaDto<long>(1, "La fecha de fin debe ser igual o posterior a la fecha de inicio.");
            fechaFin = fin;
        }

        return await repositorio.GuardarSuplenteAsync(dto, fechaInicio, fechaFin, usuario, ct);
    }

    private static bool TryFecha(string? valor, out DateTime fecha)
    {
        fecha = default;
        if (string.IsNullOrWhiteSpace(valor)) return false;
        if (!DateTime.TryParse(valor, CultureInfo.InvariantCulture, DateTimeStyles.None, out var f)) return false;
        fecha = f.Date;
        return true;
    }
}
