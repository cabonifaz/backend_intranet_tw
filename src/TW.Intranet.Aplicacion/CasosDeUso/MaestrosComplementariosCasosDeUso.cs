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

/// <summary>
/// Regla de la ubicación de una sede (pin del mapa): van la latitud y la longitud juntas, o ninguna, y dentro del recuadro de Perú
/// (latitud −18.5..−0.5, longitud −82..−68). La misma regla la repiten SP_GuardarSede y SP_ObtenerUbigeoPorCoordenadas.
/// </summary>
public static class UbicacionPeru
{
    public const string FueraDelPeru = "La ubicación debe estar dentro del Perú.";

    /// <summary>null si es válida (o si no viene ninguna y <paramref name="obligatoria"/> es false); si no, el mensaje de negocio.</summary>
    public static string? Validar(decimal? latitud, decimal? longitud, bool obligatoria)
    {
        if (latitud is null && longitud is null)
            return obligatoria ? "Indique la latitud y la longitud." : null;
        if (latitud is null || longitud is null)
            return "Envía la latitud y la longitud de la sede juntas.";
        if (latitud < -18.5m || latitud > -0.5m || longitud < -82m || longitud > -68m)
            return FueraDelPeru;
        return null;
    }
}

/// <summary>Sedes activas sin ubicación en el mapa (para completarlas): sin ellas no se valida la llegada por GPS ni se ve la planta en el seguimiento.</summary>
public class ObtenerSedesSinUbicacionCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<List<SedeSinUbicacionDto>>> EjecutarAsync(long? idCliente, CancellationToken ct = default)
    {
        if (idCliente is <= 0)
            return Task.FromResult(new RespuestaDto<List<SedeSinUbicacionDto>>(1, "El cliente no es válido."));
        return repositorio.ObtenerSedesSinUbicacionAsync(idCliente, ct);
    }
}

/// <summary>Coordenada del mapa de la sede → departamento, provincia y distrito (ubigeo INEI). El distrito lo resuelve el SP con los polígonos.</summary>
public class ObtenerUbigeoPorCoordenadasCasoDeUso(IMaestrosComplementariosRepositorio repositorio)
{
    public Task<RespuestaDto<UbigeoReversoDto?>> EjecutarAsync(decimal? latitud, decimal? longitud, CancellationToken ct = default)
    {
        var error = UbicacionPeru.Validar(latitud, longitud, obligatoria: true);
        if (error is not null)
            return Task.FromResult(new RespuestaDto<UbigeoReversoDto?>(1, error));
        return repositorio.ObtenerUbigeoPorCoordenadasAsync(Math.Round(latitud!.Value, 7), Math.Round(longitud!.Value, 7), ct);
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
