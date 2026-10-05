using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarUsuarioCasoDeUso(IUsuariosRepositorio repositorio, IHasherContrasena hasher)
{
    public async Task<RespuestaDto<long>> EjecutarAsync(
        GuardarUsuarioDto dto, long idEjecutor, CancellationToken ct = default)
    {
        // ── Validaciones de forma (las de negocio están en el SP) ──────────
        if (string.IsNullOrWhiteSpace(dto.Nombre) || string.IsNullOrWhiteSpace(dto.Apellido))
            return new RespuestaDto<long>(1, "Nombre y apellido son obligatorios.");

        if (string.IsNullOrWhiteSpace(dto.Correo) || !dto.Correo.Contains('@'))
            return new RespuestaDto<long>(1, "El correo electrónico no es válido.");

        if (string.IsNullOrWhiteSpace(dto.RolSistema))
            return new RespuestaDto<long>(1, "El rol del sistema es obligatorio.");

        if (string.IsNullOrWhiteSpace(dto.NumeroDocumento))
            return new RespuestaDto<long>(1, "El número de documento es obligatorio.");

        if (dto.IdUsuario == 0 && string.IsNullOrWhiteSpace(dto.ContrasenaTemporal))
            return new RespuestaDto<long>(1, "La contraseña temporal es obligatoria para un usuario nuevo.");

        if (dto.HabilitadoFirmaInacal && string.IsNullOrWhiteSpace(dto.NumeroRegistroInacal))
            return new RespuestaDto<long>(1, "Ingrese el número de registro INACAL para habilitar la firma.");

        DateTime? fechaExpiracion = null;
        if (!string.IsNullOrWhiteSpace(dto.FechaExpiracionCertificacion))
        {
            if (!DateTime.TryParse(dto.FechaExpiracionCertificacion, CultureInfo.InvariantCulture,
                                   DateTimeStyles.None, out var fecha))
                return new RespuestaDto<long>(1, "La fecha de expiración de la certificación no es válida.");
            fechaExpiracion = fecha.Date;
        }

        if (!string.IsNullOrWhiteSpace(dto.FechaNacimiento)
            && (!DateTime.TryParse(dto.FechaNacimiento, CultureInfo.InvariantCulture, DateTimeStyles.None, out var nac)
                || nac.Date >= DateTime.Today || nac.Year < 1900))
            return new RespuestaDto<long>(1, "La fecha de nacimiento no es válida.");

        dto.Anexo = string.IsNullOrWhiteSpace(dto.Anexo) ? null : dto.Anexo.Trim();
        if (dto.Anexo is not null && (dto.Anexo.Length > 10 || !dto.Anexo.All(char.IsDigit)))
            return new RespuestaDto<long>(1, "El anexo debe tener solo números (máximo 10 dígitos).");

        // ── Contraseña: se guarda solo el hash ─────────────────────────────
        string? passwordHash = string.IsNullOrWhiteSpace(dto.ContrasenaTemporal)
            ? null
            : hasher.Hash(dto.ContrasenaTemporal);

        dto.Correo = dto.Correo.Trim().ToLowerInvariant();

        return await repositorio.GuardarUsuarioAsync(dto, passwordHash, fechaExpiracion, idEjecutor, ct);
    }
}
