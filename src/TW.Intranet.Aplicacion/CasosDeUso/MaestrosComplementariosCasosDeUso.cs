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

// ── Áreas del cliente ────────────────────────────────────────────────────────
public class ObtenerAreasClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<AreaClienteDto>>> EjecutarAsync(long idCliente, bool soloActivas, CancellationToken ct = default)
        => repositorio.ObtenerAreasClienteAsync(idCliente, soloActivas, ct);
}

public class GuardarAreaClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<AreaClienteDto>> EjecutarAsync(
        long idCliente, GuardarAreaClienteDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Nombre))
            return Task.FromResult(new RespuestaDto<AreaClienteDto>(1, "El nombre del área es obligatorio."));
        if (dto.Nombre.Trim().Length > 150)
            return Task.FromResult(new RespuestaDto<AreaClienteDto>(1, "El nombre no puede superar los 150 caracteres."));

        return repositorio.GuardarAreaClienteAsync(idCliente, dto, idUsuario, ct);
    }
}

public class CambiarEstadoAreaClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(
        long idArea, CambiarEstadoAreaClienteDto dto, long idUsuario, CancellationToken ct = default)
    {
        var estado = dto.Estado?.Trim().ToLowerInvariant();
        if (estado is not ("activo" or "inactivo"))
            return Task.FromResult(new RespuestaDto<bool>(1, "Estado no válido. Use Activo o Inactivo."));

        return repositorio.CambiarEstadoAreaClienteAsync(idArea, estado, idUsuario, ct);
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
