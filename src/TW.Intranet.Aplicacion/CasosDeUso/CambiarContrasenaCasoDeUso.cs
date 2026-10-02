using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Cambia la contraseña del usuario autenticado. El idUsuario viene del JWT
/// (lo pasa el controller). Valida la contraseña actual contra el hash en BD,
/// chequea robustez de la nueva, hashea y actualiza en BD limpiando el flag
/// forzar_cambio_contrasena.
/// </summary>
public class CambiarContrasenaCasoDeUso(
    IAutenticacionRepositorio repositorio,
    IVerificadorContrasena    verificador,
    IHasherContrasena         hasher)
{
    public async Task<RespuestaDto<bool>> EjecutarAsync(
        long idUsuario,
        CambiarContrasenaDto dto,
        CancellationToken ct = default)
    {
        // ── Validaciones de forma ────────────────────────────────────────────
        if (string.IsNullOrWhiteSpace(dto.ContrasenaActual))
            return new RespuestaDto<bool>(1, "La contraseña actual es obligatoria.");

        if (string.IsNullOrWhiteSpace(dto.ContrasenaNueva))
            return new RespuestaDto<bool>(1, "La nueva contraseña es obligatoria.");

        if (dto.ContrasenaNueva.Length < 8)
            return new RespuestaDto<bool>(1, "La nueva contraseña debe tener al menos 8 caracteres.");

        if (!dto.ContrasenaNueva.Any(char.IsUpper))
            return new RespuestaDto<bool>(1, "La nueva contraseña debe incluir al menos una mayúscula.");

        if (!dto.ContrasenaNueva.Any(char.IsLower))
            return new RespuestaDto<bool>(1, "La nueva contraseña debe incluir al menos una minúscula.");

        if (!dto.ContrasenaNueva.Any(char.IsDigit))
            return new RespuestaDto<bool>(1, "La nueva contraseña debe incluir al menos un número.");

        if (dto.ContrasenaActual == dto.ContrasenaNueva)
            return new RespuestaDto<bool>(1, "La nueva contraseña debe ser distinta de la actual.");

        // ── Obtener hash actual del usuario ──────────────────────────────────
        var respuestaHash = await repositorio.ObtenerHashPorIdAsync(idUsuario, ct);
        if (respuestaHash.IdTipoMensaje != 2 || string.IsNullOrEmpty(respuestaHash.Datos))
            return new RespuestaDto<bool>(respuestaHash.IdTipoMensaje, respuestaHash.Mensaje);

        // ── Verificar contraseña actual con bcrypt ───────────────────────────
        if (!verificador.Verificar(dto.ContrasenaActual, respuestaHash.Datos))
            return new RespuestaDto<bool>(1, "La contraseña actual es incorrecta.");

        // ── Hashear nueva y actualizar en BD ─────────────────────────────────
        string hashNuevo = hasher.Hash(dto.ContrasenaNueva);
        return await repositorio.CambiarContrasenaAsync(idUsuario, hashNuevo, ct);
    }
}
