using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>Directorio interno (#4303): contactos de los usuarios activos.</summary>
public class ObtenerDirectorioCasoDeUso(IDirectorioRepositorio repositorio)
{
    public Task<RespuestaDto<DirectorioPaginadoDto>> EjecutarAsync(
        string? busqueda, string? area, int pagina, int porPagina, CancellationToken ct = default)
        => repositorio.ObtenerDirectorioAsync(
            busqueda?.Trim(), area?.Trim().ToLowerInvariant(),
            Math.Max(pagina, 1), Math.Clamp(porPagina, 1, 200), ct);
}

/// <summary>Cumpleaños del mes (#4303, RR. HH.).</summary>
public class ObtenerCumpleanosCasoDeUso(IDirectorioRepositorio repositorio)
{
    public Task<RespuestaDto<List<CumpleanosItemDto>>> EjecutarAsync(int? mes, CancellationToken ct = default)
    {
        var m = mes ?? DateTime.Today.Month;
        if (m is < 1 or > 12)
            return Task.FromResult(new RespuestaDto<List<CumpleanosItemDto>>(1, "El mes debe estar entre 1 y 12."));
        return repositorio.ObtenerCumpleanosAsync(m, ct);
    }
}

/// <summary>
/// Evitar duplicados (#4290): compara lo que el usuario escribe con los valores ya registrados
/// y devuelve los parecidos. Puntaje ≥ 85 = probable duplicado, 70–84 = parecido.
/// </summary>
public class VerificarDuplicadosCasoDeUso(IDirectorioRepositorio repositorio)
{
    private static readonly string[] Campos = ["tipo_suministro", "subtipo", "marca", "modelo", "area_cliente"];

    public async Task<RespuestaDto<VerificacionDuplicadosDto>> EjecutarAsync(
        string? campo, string? texto, long? idCliente, CancellationToken ct = default)
    {
        var c = campo?.Trim().ToLowerInvariant() ?? "";
        if (!Campos.Contains(c))
            return new RespuestaDto<VerificacionDuplicadosDto>(1, $"Campo no válido. Use: {string.Join(", ", Campos)}.");
        if (c == "area_cliente" && (idCliente ?? 0) <= 0)
            return new RespuestaDto<VerificacionDuplicadosDto>(1, "Para áreas indique el idCliente.");

        var t = texto?.Trim() ?? "";
        if (Similitud.Normalizar(t).Length < 2)
            return new RespuestaDto<VerificacionDuplicadosDto>(2, "Escriba al menos 2 caracteres.",
                new VerificacionDuplicadosDto(t, false, []));

        var valores = await repositorio.ObtenerValoresExistentesAsync(c, idCliente, ct);
        if (valores.IdTipoMensaje != 2 || valores.Datos is null)
            return new RespuestaDto<VerificacionDuplicadosDto>(valores.IdTipoMensaje, valores.Mensaje);

        var similares = valores.Datos
            .Select(v => new { v, puntaje = Similitud.Puntaje(t, v.Valor) })
            .Where(x => x.puntaje >= Similitud.UmbralParecido)
            .OrderByDescending(x => x.puntaje).ThenByDescending(x => x.v.Usos)
            .Take(8)
            .Select(x => new ValorSimilarDto(x.v.Valor, x.v.Detalle, x.v.Usos, x.puntaje,
                                             x.puntaje >= Similitud.UmbralDuplicado))
            .ToList();

        var exacto  = similares.Any(s => s.Similitud == 100);
        var mensaje = exacto ? $"Ya existe \"{similares.First(s => s.Similitud == 100).Valor}\"."
                    : similares.Any(s => s.ProbableDuplicado) ? "Hay valores muy parecidos: revise antes de crear uno nuevo."
                    : similares.Count > 0 ? "Hay valores parecidos."
                    : "No hay valores parecidos.";

        return new RespuestaDto<VerificacionDuplicadosDto>(2, mensaje, new VerificacionDuplicadosDto(t, exacto, similares));
    }
}
