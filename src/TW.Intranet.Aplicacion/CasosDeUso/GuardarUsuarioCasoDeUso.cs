using System.Globalization;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

public class GuardarUsuarioCasoDeUso(IUsuariosRepositorio repositorio, IHasherContrasena hasher)
{
    private static readonly string[] Troncales = ["5699750", "5699751"];

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

        dto.Anexo   = string.IsNullOrWhiteSpace(dto.Anexo)   ? null : dto.Anexo.Trim().Replace("-", "").Replace(" ", "");
        dto.Troncal = string.IsNullOrWhiteSpace(dto.Troncal) ? null : dto.Troncal.Trim().Replace("-", "");

        // El front envía el anexo completo: troncal (7) + interno (3), ej. "5699750207".
        if (dto.Anexo is { Length: 10 } && Troncales.Any(t => dto.Anexo.StartsWith(t)))
        {
            dto.Troncal = dto.Anexo[..7];
            dto.Anexo   = dto.Anexo[7..];
        }
        if (dto.Anexo is not null && (dto.Anexo.Length != 3 || !dto.Anexo.All(char.IsDigit)))
            return new RespuestaDto<long>(1, "El anexo debe tener 3 dígitos.");
        if (dto.Anexo is not null && dto.Troncal is null)
            return new RespuestaDto<long>(1, "Seleccione la troncal del anexo (569-9750 o 569-9751).");
        if (dto.Anexo is null)
            dto.Troncal = null;

        // La sede está oculta en el front (Lima por defecto); se acepta el alias "lima".
        if (string.Equals(dto.SedeOperativa?.Trim(), "lima", StringComparison.OrdinalIgnoreCase))
            dto.SedeOperativa = "lima_central";

        // ── Contraseña: se guarda solo el hash ─────────────────────────────
        string? passwordHash = string.IsNullOrWhiteSpace(dto.ContrasenaTemporal)
            ? null
            : hasher.Hash(dto.ContrasenaTemporal);

        dto.Correo = dto.Correo.Trim().ToLowerInvariant();

        return await repositorio.GuardarUsuarioAsync(dto, passwordHash, fechaExpiracion, idEjecutor, ct);
    }
}
