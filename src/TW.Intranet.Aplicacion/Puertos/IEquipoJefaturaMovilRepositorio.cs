using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Lo que lee el SP de las horas contabilizadas: todo menos las semanas, que arma el caso de uso a partir de los días (cálculo puro).</summary>
public record HorasTecnicoLecturaDto(EquipoTecnicoDto Tecnico, string Mes, List<HoraDiaDto> Dias, int TotalMinutos, int DiasTrabajados, int Servicios, bool Cerrado, List<HoraMesDto> Historial);

/// <summary>Mi equipo: asistencia, ubicación y horas contabilizadas de los técnicos del Jefe de Área en la app móvil (App Mobile HU-36). Todo sale de procedimientos almacenados.</summary>
public interface IEquipoJefaturaMovilRepositorio
{
    Task<RespuestaDto<EquipoJefaturaDto>> ObtenerAsync(long idUsuario, CancellationToken ct);

    Task<RespuestaDto<FichaEquipoTecnicoDto>> ObtenerFichaAsync(long idUsuario, long idTecnico, CancellationToken ct);

    /// <summary>mes = «AAAA-MM» ya validado (null = el mes actual de Lima).</summary>
    Task<RespuestaDto<HorasTecnicoLecturaDto>> ObtenerHorasAsync(long idUsuario, long idTecnico, string? mes, CancellationToken ct);
}
