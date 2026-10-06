using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── Ubigeo ───────────────────────────────────────────────────────────────────
public class ObtenerUbigeoCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<UbigeoItemDto>>> EjecutarAsync(
        string nivel, string? departamento, string? provincia, CancellationToken ct = default)
    {
        if (nivel == "provincias" && string.IsNullOrWhiteSpace(departamento))
            return Task.FromResult(new RespuestaDto<List<UbigeoItemDto>>(1, "Indique el departamento."));
        if (nivel == "distritos" && (string.IsNullOrWhiteSpace(departamento) || string.IsNullOrWhiteSpace(provincia)))
            return Task.FromResult(new RespuestaDto<List<UbigeoItemDto>>(1, "Indique el departamento y la provincia."));

        return repositorio.ObtenerUbigeoAsync(nivel, departamento?.Trim(), provincia?.Trim(), ct);
    }
}

// ── Áreas asignadas al cliente ───────────────────────────────────────────────
public class ObtenerAreasClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<AreaClienteDto>>> EjecutarAsync(long idCliente, CancellationToken ct = default)
        => repositorio.ObtenerAreasClienteAsync(idCliente, ct);
}

// ── Próximo código de ficha (modo "nuevo") ──────────────────────────────────
public class ObtenerSiguienteCodigoCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    private static readonly string[] Entidades = ["requerimiento", "propuesta", "suministro", "equipo_cliente"];

    public Task<RespuestaDto<SiguienteCodigoDto>> EjecutarAsync(string entidad, CancellationToken ct = default)
    {
        var e = entidad?.Trim().ToLowerInvariant() ?? "";
        if (!Entidades.Contains(e))
            return Task.FromResult(new RespuestaDto<SiguienteCodigoDto>(1,
                $"Entidad no válida. Use: {string.Join(", ", Entidades)}."));
        return repositorio.ObtenerSiguienteCodigoAsync(e, ct);
    }
}

// ── Códigos de formato por ventana ───────────────────────────────────────────
public class ObtenerFormatosVentanaCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<FormatoVentanaDto>>> EjecutarAsync(string? clave, CancellationToken ct = default)
        => repositorio.ObtenerFormatosVentanaAsync(clave, ct);
}

public class GuardarFormatoVentanaCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(
        string clave, GuardarFormatoVentanaDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(clave) || clave.Length > 80)
            return Task.FromResult(new RespuestaDto<bool>(1, "La clave de la ventana no es válida."));
        if (dto.CodigoFormato?.Trim().Length > 40)
            return Task.FromResult(new RespuestaDto<bool>(1, "El código no puede superar los 40 caracteres."));
        if (dto.Version is < 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "La versión no puede ser negativa."));

        return repositorio.GuardarFormatoVentanaAsync(clave.Trim().ToLowerInvariant(), dto, idUsuario, ct);
    }
}
