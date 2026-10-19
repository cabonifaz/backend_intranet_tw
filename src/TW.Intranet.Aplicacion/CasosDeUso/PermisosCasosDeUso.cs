using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>Permisos del usuario que inició sesión (menú y acciones del front).</summary>
public class ObtenerMisPermisosCasoDeUso(IPermisosRepositorio repositorio)
{
    public Task<RespuestaDto<List<PermisoModuloDto>>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<List<PermisoModuloDto>>(1, "Sesión no válida."))
            : repositorio.ObtenerPermisosUsuarioAsync(idUsuario, ct);
}

/// <summary>Matriz de permisos de un área + rol (pantalla de configuración).</summary>
public class ObtenerPermisosAreaRolCasoDeUso(IPermisosRepositorio repositorio)
{
    public Task<RespuestaDto<List<PermisoModuloDto>>> EjecutarAsync(string? area, string? rol, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(area) || string.IsNullOrWhiteSpace(rol))
            return Task.FromResult(new RespuestaDto<List<PermisoModuloDto>>(1, "Indique el área y el rol."));
        return repositorio.ObtenerPermisosAreaRolAsync(area.Trim().ToLowerInvariant(), rol.Trim().ToLowerInvariant(), ct);
    }
}

/// <summary>Define o quita una excepción de acceso (área + rol + módulo).</summary>
public class GuardarPermisoCasoDeUso(IPermisosRepositorio repositorio)
{
    private static readonly string[] Accesos = ["ninguno", "ver", "editar", "supervisar", "administrar"];

    public Task<RespuestaDto<bool>> EjecutarAsync(GuardarPermisoDto dto, long idUsuario, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Area) || string.IsNullOrWhiteSpace(dto.Rol) || string.IsNullOrWhiteSpace(dto.Modulo))
            return Task.FromResult(new RespuestaDto<bool>(1, "Indique el área, el rol y el módulo."));

        dto.Area   = dto.Area.Trim().ToLowerInvariant();
        dto.Rol    = dto.Rol.Trim().ToLowerInvariant();
        dto.Modulo = dto.Modulo.Trim().ToLowerInvariant();
        dto.Acceso = string.IsNullOrWhiteSpace(dto.Acceso) ? null : dto.Acceso.Trim().ToLowerInvariant();

        if (dto.Acceso is not null && !Accesos.Contains(dto.Acceso))
            return Task.FromResult(new RespuestaDto<bool>(1, "Acceso no válido. Use ninguno, ver, editar, supervisar o administrar."));

        return repositorio.GuardarPermisoAsync(dto, idUsuario, ct);
    }
}

/// <summary>Acciones que puede ejecutar el usuario que inició sesión (botones del front y validación del back).</summary>
public class ObtenerMisAccionesCasoDeUso(IPermisosRepositorio repositorio)
{
    public Task<RespuestaDto<List<AccionPermitidaDto>>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<List<AccionPermitidaDto>>(1, "Sesión no válida."))
            : repositorio.ObtenerAccionesUsuarioAsync(idUsuario, ct);
}
