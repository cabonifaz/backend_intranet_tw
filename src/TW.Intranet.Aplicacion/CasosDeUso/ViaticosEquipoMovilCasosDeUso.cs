using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-35 — Viáticos y gastos del equipo (Jefe de Área) ──────────────────────────────────────────────────

/// <summary>
/// Validación de entrada de "Asignar viático". Desarrollo seguro: técnico obligatorio, montos no negativos con hasta 2 decimales, al menos un monto mayor a 0 y versión con formato acotado.
/// El tope por línea (VIATICOS_MONTO_MAXIMO), el personal del servicio, la programación confirmada, la rendición abierta, la concurrencia y los viáticos depositados los valida el SP
/// (SP_AsignarViaticoEquipoMovil → SP_GuardarViaticosProgramacion de la intranet).
/// </summary>
public static class ValidacionViaticosEquipoMovil
{
    /// <summary>Tope técnico de cualquier monto aceptado por la API (el tope de negocio lo pone el SP): evita desbordar DECIMAL(12,2).</summary>
    public const decimal MontoTecnicoMaximo = 9_999_999m;
    public const int MaxVersion = 80;

    private static bool TieneMasDeDosDecimales(decimal m) => decimal.Round(m, 2) != m;

    /// <summary>Devuelve el error o los valores normalizados (montos con 2 decimales, vacío = 0; versión sin espacios).</summary>
    public static (string? Error, long IdTecnico, decimal Movilidad, decimal Alimentacion, decimal Alojamiento, decimal Otros, bool Depositado, string Version)
        NormalizarAsignacion(AsignarViaticoEquipoDto? d)
    {
        static (string?, long, decimal, decimal, decimal, decimal, bool, string) Falla(string mensaje) => (mensaje, 0, 0, 0, 0, 0, false, "");

        if (d is null) return Falla("Indica el técnico y los montos del viático.");
        if (d.IdTecnico is not > 0) return Falla("Elige el técnico al que se asigna el viático.");

        var montos = new[] { d.Movilidad ?? 0m, d.Alimentacion ?? 0m, d.Alojamiento ?? 0m, d.Otros ?? 0m };
        if (montos.Any(m => m < 0)) return Falla("Los montos no pueden ser negativos.");
        if (montos.Any(m => m > MontoTecnicoMaximo)) return Falla("Alguno de los montos es demasiado grande.");
        if (montos.Any(TieneMasDeDosDecimales)) return Falla("Los montos admiten hasta 2 decimales.");
        if (montos.Sum() <= 0) return Falla("Indica al menos un monto mayor a 0.");

        var version = (d.Version ?? "").Trim();
        if (version.Length == 0) return Falla("Falta la versión de la asignación: vuelve a abrir los viáticos del servicio.");
        if (version.Length > MaxVersion || version.Any(char.IsControl)) return Falla("La versión de la asignación no es válida: vuelve a abrir los viáticos del servicio.");

        return (null, d.IdTecnico.Value, montos[0], montos[1], montos[2], montos[3], d.Depositado ?? false, version);
    }
}

/// <summary>Lista "Viáticos y gastos del equipo": KPIs y un resumen por servicio (asignado, rendido y por revisar), con el alcance Área + Rol del jefe.</summary>
public class ObtenerViaticosEquipoMovilCasoDeUso(IViaticosEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ViaticosEquipoDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default) =>
        idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<ViaticosEquipoDto>(1, "No se pudo identificar al usuario."))
            : repositorio.ObtenerAsync(idUsuario, ct);
}

/// <summary>Detalle de un servicio: técnicos con sus líneas de viáticos, gastos rendidos con el comprobante y la lectura de la IA, y la versión para asignar.</summary>
public class ObtenerViaticoServicioEquipoMovilCasoDeUso(IViaticosEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ViaticoServicioDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default) =>
        idUsuario <= 0 ? Task.FromResult(new RespuestaDto<ViaticoServicioDto>(1, "No se pudo identificar al usuario."))
        : idOs <= 0    ? Task.FromResult(new RespuestaDto<ViaticoServicioDto>(1, "El servicio indicado no es válido."))
        : repositorio.ObtenerServicioAsync(idUsuario, idOs, ct);
}

/// <summary>Asignar viático a un técnico del servicio (y, si el jefe lo pide, dejarlo depositado). Las reglas de negocio las valida el SP con las de la intranet (HU-45).</summary>
public class AsignarViaticoEquipoMovilCasoDeUso(IViaticosEquipoMovilRepositorio repositorio)
{
    public Task<RespuestaDto<AsignacionViaticoResultadoDto>> EjecutarAsync(long idUsuario, long idOs, AsignarViaticoEquipoDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0) return Task.FromResult(new RespuestaDto<AsignacionViaticoResultadoDto>(1, "No se pudo identificar al usuario."));
        if (idOs <= 0)      return Task.FromResult(new RespuestaDto<AsignacionViaticoResultadoDto>(1, "El servicio indicado no es válido."));
        var v = ValidacionViaticosEquipoMovil.NormalizarAsignacion(dto);
        if (v.Error is not null) return Task.FromResult(new RespuestaDto<AsignacionViaticoResultadoDto>(1, v.Error));
        return repositorio.AsignarAsync(idUsuario, idOs, v.IdTecnico, v.Movilidad, v.Alimentacion, v.Alojamiento, v.Otros, v.Depositado, v.Version, ct);
    }
}
