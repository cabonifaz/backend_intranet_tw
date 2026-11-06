using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-28 / HU-31 — Menú de Jefatura y Centro de aprobaciones ────────────────────

/// <summary>
/// Menú de Jefatura: resumen del día del área del jefe que inició sesión. El SP valida el cargo (hoy, Jefe de Metrología) y filtra
/// por el área según la RQ; a quien no es jefe de un área con Jefatura le responde que no tiene ese menú.
/// </summary>
public class ObtenerMenuJefaturaMovilCasoDeUso(IMenuMovilRepositorio repositorio)
{
    public Task<RespuestaDto<MenuJefaturaMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<MenuJefaturaMovilDto>(1, "No se pudo identificar al usuario."));

        return repositorio.ObtenerMenuJefaturaAsync(idUsuario, ct);
    }
}

/// <summary>Fecha de hoy en Lima (UTC-5, sin horario de verano): misma regla que usan los SP.</summary>
internal static class HoraLima
{
    public static string Hoy(DateTime? ahoraUtc = null) => (ahoraUtc ?? DateTime.UtcNow).AddHours(-5).ToString("yyyy-MM-dd");
}

/// <summary>
/// Centro de aprobaciones: una sola bandeja con lo que espera la decisión del jefe. Hoy reúne las solicitudes de salida de los
/// técnicos (HU-04); las evidencias forzadas, los ensayos con error y los gastos se suman cuando existan sus módulos.
/// Reutiliza el SP de la intranet, que ya filtra por el área del jefe según la RQ. Urgentes primero (el servicio es de hoy).
/// </summary>
public class ObtenerAprobacionesMovilCasoDeUso(IAutorizacionSalidaRepositorio autorizaciones)
{
    public async Task<RespuestaDto<AprobacionesMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return new(1, "No se pudo identificar al usuario.");

        var r = await autorizaciones.ObtenerAsync(idUsuario, "pendiente", ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null)
            return new(r.IdTipoMensaje, r.Mensaje);

        return new(2, r.Mensaje, Armar(r.Datos, HoraLima.Hoy()));
    }

    /// <summary>Convierte las solicitudes pendientes en la bandeja (pública para poder probarla sin base de datos).</summary>
    public static AprobacionesMovilDto Armar(IEnumerable<AutorizacionSalidaBandejaDto> pendientes, string hoy)
    {
        var items = pendientes
            .Where(a => a.Estado == "pendiente")
            .Select(a => new AprobacionMovilDto(
                "salida", a.IdOs, "Autorización de salida", a.NumeroOs, a.Tecnico, a.Cliente,
                string.IsNullOrWhiteSpace(a.Pendientes) ? "Sin pendientes indicados" : $"falta: {a.Pendientes}",
                a.FechaEjecucion, a.HoraInicio,
                Urgente: a.FechaEjecucion is { Length: >= 10 } f && f[..10] == hoy,
                a.SolicitadaEn))
            .OrderByDescending(i => i.Urgente)
            .ThenByDescending(i => i.SolicitadaEn)
            .ToList();

        var tipos = new List<TipoAprobacionMovilDto> { new("salida", items.Count) };
        return new AprobacionesMovilDto(items.Count, items.Count(i => i.Urgente), tipos, items);
    }
}

/// <summary>
/// Solicitud de salida del técnico con su checklist (sus pendientes y el motivo), para que el jefe decida.
/// Solo la ve el jefe del área según la RQ (lo filtra el SP). El checklist se arma con las mismas reglas que ve el técnico.
/// </summary>
public class ObtenerAprobacionSalidaMovilCasoDeUso(IAutorizacionSalidaRepositorio autorizaciones, IPresalidaMovilRepositorio presalida)
{
    public async Task<RespuestaDto<AprobacionSalidaMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        const string noEncontrada = "No se encontró la solicitud de salida o no corresponde a tu área.";
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, noEncontrada);

        var lista = await autorizaciones.ObtenerAsync(idUsuario, string.Empty, ct);
        if (lista.IdTipoMensaje != 2 || lista.Datos is null)
            return new(lista.IdTipoMensaje, lista.Mensaje);

        // La solicitud pendiente de la OS; si ya se resolvió, la más reciente (el SP trae primero las pendientes y las más nuevas).
        var solicitud = lista.Datos.FirstOrDefault(a => a.IdOs == idOs);
        if (solicitud is null || solicitud.IdTecnico <= 0)
            return new(1, noEncontrada);

        var hechos = await presalida.ObtenerHechosChecklistAsync(solicitud.IdTecnico, idOs, ct);
        if (hechos.IdTipoMensaje != 2 || hechos.Datos is null)
            return new(hechos.IdTipoMensaje, hechos.Mensaje);

        var checklist = ReglasChecklistSalida.Evaluar(hechos.Datos);
        var items = checklist.Items.Where(i => i.Codigo != "visto_bueno").ToList();
        return new(2, lista.Mensaje, new AprobacionSalidaMovilDto(solicitud, items, checklist.Faltantes, checklist.AreaAutoriza.Area));
    }
}

/// <summary>
/// El jefe autoriza la salida con una condición o la rechaza con un motivo (siempre obligatorio, 3 a 500 caracteres).
/// El SP valida que sea el encargado del área según la RQ, notifica al técnico al instante y deja la decisión en la auditoría.
/// </summary>
public class ResolverAprobacionSalidaMovilCasoDeUso(IAutorizacionSalidaRepositorio autorizaciones)
{
    public const int MinTexto = 3;
    public const int MaxTexto = 500;

    public Task<RespuestaDto<bool>> EjecutarAsync(long idJefe, long idOs, ResolverAutorizacionSalidaDto? dto, CancellationToken ct = default)
    {
        if (idJefe <= 0 || idOs <= 0 || dto is null)
            return Task.FromResult(new RespuestaDto<bool>(1, "Datos incompletos."));

        var texto = SolicitarAutorizacionSalidaMovilCasoDeUso.Limpiar(dto.Comentario);
        if (texto is null || texto.Length < MinTexto)
            return Task.FromResult(new RespuestaDto<bool>(1, dto.Aprobar
                ? "Indica la condición con la que autorizas la salida."
                : "Indica el motivo por el que no autorizas la salida."));
        if (texto.Length > MaxTexto)
            return Task.FromResult(new RespuestaDto<bool>(1, $"El texto puede tener hasta {MaxTexto} caracteres."));

        return autorizaciones.ResolverAsync(idJefe, idOs, dto.Aprobar, texto, ct);
    }
}
