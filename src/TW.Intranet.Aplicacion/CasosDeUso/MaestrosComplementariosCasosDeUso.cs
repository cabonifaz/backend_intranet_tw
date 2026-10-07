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

// ── Áreas por cliente (nombres libres, no catálogo global) ──────────────────
public class ObtenerAreasClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<AreaClienteDto>>> EjecutarAsync(
        long idCliente, bool soloActivas, CancellationToken ct = default)
        => repositorio.ObtenerAreasClienteAsync(idCliente, soloActivas, ct);
}

public class GuardarAreaClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<AreaClienteDto?>> EjecutarAsync(
        long idCliente, GuardarAreaClienteDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idCliente <= 0)
            return Task.FromResult(new RespuestaDto<AreaClienteDto?>(1, "Cliente no válido."));
        var nombre = dto.Nombre?.Trim() ?? "";
        if (nombre.Length < 2)
            return Task.FromResult(new RespuestaDto<AreaClienteDto?>(1, "El nombre del área debe tener al menos 2 caracteres."));
        if (nombre.Length > 150)
            return Task.FromResult(new RespuestaDto<AreaClienteDto?>(1, "El nombre del área no puede superar los 150 caracteres."));
        return repositorio.GuardarAreaClienteAsync(idCliente, dto, idUsuario, ct);
    }
}

public class CambiarEstadoAreaClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(
        long idArea, CambiarEstadoAreaClienteDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idArea <= 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "Área no válida."));
        var estado = dto.Estado?.Trim();
        if (string.IsNullOrEmpty(estado) ||
            !(estado.Equals("Activo", StringComparison.OrdinalIgnoreCase) ||
              estado.Equals("Inactivo", StringComparison.OrdinalIgnoreCase)))
            return Task.FromResult(new RespuestaDto<bool>(1, "El estado debe ser \"Activo\" o \"Inactivo\"."));
        return repositorio.CambiarEstadoAreaClienteAsync(idArea, dto, idUsuario, ct);
    }
}

// ── Requisitos SSOMA asignados al cliente ────────────────────────────────────
public class ObtenerRequisitosDelClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<RequisitoSsomaClienteDto>>> EjecutarAsync(long idCliente, CancellationToken ct = default)
    {
        if (idCliente <= 0)
            return Task.FromResult(new RespuestaDto<List<RequisitoSsomaClienteDto>>(1, "Cliente no válido."));
        return repositorio.ObtenerRequisitosDelClienteAsync(idCliente, ct);
    }
}

public class SincronizarRequisitosClienteCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<bool>> EjecutarAsync(
        long idCliente, SincronizarRequisitosSsomaDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (idCliente <= 0)
            return Task.FromResult(new RespuestaDto<bool>(1, "Cliente no válido."));
        // dto.Codigos puede ser null (no cambiar) o lista (reemplazar — vacío borra todos).
        return repositorio.SincronizarRequisitosClienteAsync(idCliente, dto, idUsuario, ct);
    }
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
