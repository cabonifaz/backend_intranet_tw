using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// App Mobile HU-03 — Agenda de servicios programados del técnico.
/// Filtros: todos | hoy | pendientes | en_ejecucion. Búsqueda por N° de OS, RQ, OM o cliente.
/// </summary>
public class ObtenerServiciosProgramadosMovilCasoDeUso(IServiciosMovilRepositorio repositorio)
{
    private static readonly HashSet<string> FiltrosValidos = ["todos", "hoy", "pendientes", "en_ejecucion"];

    public Task<RespuestaDto<List<ServicioProgramadoMovilDto>>> EjecutarAsync(
        long idUsuario, string? filtro, string? busqueda, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<List<ServicioProgramadoMovilDto>>(1, "No se pudo identificar al usuario."));

        var filtroNormalizado = string.IsNullOrWhiteSpace(filtro) ? "todos" : filtro.Trim().ToLowerInvariant();
        if (!FiltrosValidos.Contains(filtroNormalizado))
            return Task.FromResult(new RespuestaDto<List<ServicioProgramadoMovilDto>>(
                1, "Filtro no válido. Use todos, hoy, pendientes o en_ejecucion."));

        var texto = busqueda?.Trim();
        if (texto is { Length: > 100 }) texto = texto[..100];

        return repositorio.ObtenerProgramadosAsync(idUsuario, filtroNormalizado, texto, ct);
    }
}
