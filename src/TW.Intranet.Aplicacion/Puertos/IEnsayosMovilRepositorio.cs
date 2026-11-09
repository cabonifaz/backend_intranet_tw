using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Ensayos y Calibración de la app móvil (App Mobile HU-10).</summary>
public interface IEnsayosMovilRepositorio
{
    Task<RespuestaDto<EnsayosMovilDto>> ObtenerAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct);

    /// <summary>json: {"pesaje":[{"carga","indicacion"}],"excentricidad":[{"carga","lecturas":[…]}]} ya validado por el caso de uso.</summary>
    Task<RespuestaDto<ResultadoGuardarEnsayosMovilDto>> GuardarAsync(
        long idUsuario, long idOs, long idOsEquipo, string formaPlato, string json, string? motivo, bool finalizar, CancellationToken ct);

    Task<RespuestaDto<ResultadoLlamadaEnsayoMovilDto>> RegistrarLlamadaAsync(long idUsuario, long idOs, long idOsEquipo, string? detalle, CancellationToken ct);
}
