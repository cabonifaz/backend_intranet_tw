using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-04 — Detalle del servicio y checklist de pre-salida ──────────

/// <summary>
/// Reglas del checklist de pre-salida (una sola fuente: la usan la consulta y el inicio del traslado,
/// así la app nunca decide sola si se puede salir).
///   Obligatorios: expediente revisado, cliente confirmó visita, SSOMA, EPP, materiales e insumos,
///                 herramientas, pesas patrón (solo calibración / verificación metrológica),
///                 repuestos asignados y alertas predictivas resueltas.
///   Opcional:     OC cargada.
///   Visto bueno del encargado del área del servicio según la RQ (Jefe de Servicio Técnico o
///   Jefe de Metrología; lo da desde la intranet): con él se puede salir aunque queden
///   obligatorios pendientes.
/// </summary>
public static class ReglasChecklistSalida
{
    /// <summary>Ítems que confirma el técnico (lista blanca).</summary>
    public static readonly IReadOnlySet<string> CodigosManuales =
        new HashSet<string> { "expediente", "epp", "materiales", "herramientas", "pesas_patron" };

    /// <summary>Calibración (3) y Verificación metrológica (4) llevan pesas patrón (catálogo TIPO_SERVICIO).</summary>
    public static bool RequierePesasPatron(int idTipoServicio) => idTipoServicio is 3 or 4;

    public static bool EstaProgramada(string estadoOs) => estadoOs is "programada" or "reprogramada";

    public static ChecklistSalidaMovilDto Evaluar(HechosChecklistSalidaDto h)
    {
        var editable = EstaProgramada(h.EstadoOs);
        var items = new List<ItemChecklistSalidaDto>
        {
            Manual("expediente", "Expediente revisado", h.ExpedienteRevisado, editable,
                   "Revisa el RQ, la OS y los documentos del servicio."),
            Automatico("cliente_confirmo", "Cliente confirmó visita", true,
                       h.ClienteConfirmado ? "conforme" : "pendiente",
                       h.ClienteConfirmado ? null : "Coordina la visita con el cliente o con Programación."),
            Automatico("ssoma", "SSOMA completo", true,
                       h.EstadoSsoma switch { "habilitado" => "conforme", "bloqueado" => "bloqueado", _ => "pendiente" },
                       h.EstadoSsoma switch
                       {
                           "habilitado" => null,
                           "bloqueado"  => "Tu SSOMA está bloqueado para este servicio. Comunícate con SSOMA.",
                           _            => "Falta aprobar tus documentos SSOMA para este servicio.",
                       }),
            Automatico("oc", "OC cargada", false,
                       h.TieneOc ? "conforme" : "opcional",
                       h.TieneOc ? null : "No es obligatoria para salir."),
            Manual("epp", "EPP revisado", h.EppRevisado, editable, "Casco, lentes, zapatos, guantes y lo que pida el cliente."),
            Manual("materiales", "Materiales e insumos", h.MaterialesListos, editable, "Consumibles e insumos del servicio."),
            Manual("herramientas", "Herramientas listas", h.HerramientasListas, editable, null),
        };

        items.Add(RequierePesasPatron(h.IdTipoServicio)
            ? Manual("pesas_patron", "Pesas patrón asignadas", h.PesasPatronAsignadas, editable, "Verifica certificado vigente.")
            : new ItemChecklistSalidaDto("pesas_patron", "Pesas patrón asignadas", "manual", false, "no_aplica",
                                         "Este tipo de servicio no usa pesas patrón.", false));

        items.Add(Automatico("repuestos", "Repuestos asignados", true,
            h.RepuestosTotal == 0 ? "no_aplica" : h.RepuestosPendientes > 0 ? "pendiente" : "conforme",
            h.RepuestosTotal == 0 ? "El servicio no tiene repuestos asignados."
            : h.RepuestosPendientes > 0 ? $"{h.RepuestosPendientes} de {h.RepuestosTotal} repuestos sin asignar." : null));

        items.Add(Automatico("alerta", "Alerta predictiva", true,
            h.AlertasPendientes > 0 ? "bloqueado" : "conforme",
            h.AlertasPendientes > 0 ? $"{h.AlertasPendientes} alerta(s) predictiva(s) sin resolver." : null));

        var autorizacion = h.AutorizacionEstado is null
            ? null
            : new AutorizacionSalidaDto(h.AutorizacionEstado, h.AutorizacionJefe, h.AutorizacionComentario,
                                        h.AutorizacionSolicitadaEn, h.AutorizacionResueltaEn);

        var area = new AreaAutorizaSalidaDto(h.AreaAutorizaCodigo, h.AreaAutoriza, h.CargoEncargado, h.EncargadoArea);
        var quienAutoriza = area.Cargo ?? "Encargado del área";
        var aQuien = area.Cargo is null
            ? "a los encargados de Servicio Técnico y Metrología"
            : $"al {area.Cargo}" + (string.IsNullOrWhiteSpace(area.Encargado) ? "" : $" ({area.Encargado})");

        items.Add(new ItemChecklistSalidaDto("visto_bueno", $"Visto bueno {quienAutoriza}", "autorizacion", false,
            autorizacion?.Estado switch
            {
                "aprobada"  => "conforme",
                "rechazada" => "bloqueado",
                "pendiente" => "pendiente",
                _           => "opcional",
            },
            autorizacion?.Estado switch
            {
                "aprobada"  => $"Aprobado por {autorizacion.Jefe ?? "el jefe"}." + (string.IsNullOrWhiteSpace(autorizacion.Comentario) ? "" : $" {autorizacion.Comentario}"),
                "rechazada" => $"No autorizado por {autorizacion.Jefe ?? "el jefe"}." + (string.IsNullOrWhiteSpace(autorizacion.Comentario) ? "" : $" {autorizacion.Comentario}"),
                "pendiente" => $"Solicitud enviada {aQuien}: esperando respuesta.",
                _           => area.Cargo is null
                               ? "La RQ no indica el área: lo marca el encargado de Servicio Técnico o de Metrología desde la intranet."
                               : $"Lo marca el {area.Cargo} desde la intranet. Solo hace falta si quedan pendientes.",
            },
            false));

        var faltantes = items
            .Where(i => i.Obligatorio && i.Estado is "pendiente" or "bloqueado")
            .Select(i => i.Nombre)
            .ToList();

        var vistoBuenoVigente = autorizacion?.Estado == "aprobada";
        var completo          = faltantes.Count == 0;
        var puedeIniciar      = editable && (completo || vistoBuenoVigente);

        return new ChecklistSalidaMovilDto(
            h.IdOs, h.NumeroOs, h.Cliente, h.FechaEjecucion, h.HoraInicio, h.Tecnico, h.EstadoOs,
            items,
            faltantes,
            PuedeIniciar:               puedeIniciar,
            SaleConVistoBueno:          puedeIniciar && !completo,
            PuedeSolicitarAutorizacion: editable && !completo && autorizacion?.Estado is not ("pendiente" or "aprobada"),
            TrasladoIniciado:           !editable && h.EstadoOs is "en_ruta" or "en_ejecucion" or "pausada" or "finalizada",
            Autorizacion:               autorizacion,
            AreaAutoriza:               area);
    }

    private static ItemChecklistSalidaDto Manual(string codigo, string nombre, bool confirmado, bool editable, string? detalle) =>
        new(codigo, nombre, "manual", true, confirmado ? "conforme" : "pendiente", detalle, editable);

    private static ItemChecklistSalidaDto Automatico(string codigo, string nombre, bool obligatorio, string estado, string? detalle) =>
        new(codigo, nombre, "automatico", obligatorio, estado, detalle, false);
}

/// <summary>Detalle de una OS del técnico que inició sesión (el id del técnico sale del token).</summary>
public class ObtenerDetalleServicioMovilCasoDeUso(IPresalidaMovilRepositorio repositorio)
{
    public Task<RespuestaDto<DetalleServicioMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return Task.FromResult(new RespuestaDto<DetalleServicioMovilDto>(1, "Servicio no encontrado o no asignado a tu usuario."));

        return repositorio.ObtenerDetalleAsync(idUsuario, idOs, ct);
    }
}

/// <summary>Checklist de pre-salida con el estado de cada ítem y si se puede iniciar el traslado.</summary>
public class ObtenerChecklistSalidaMovilCasoDeUso(IPresalidaMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<ChecklistSalidaMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, "Servicio no encontrado o no asignado a tu usuario.");

        var hechos = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        if (hechos.IdTipoMensaje != 2 || hechos.Datos is null)
            return new(hechos.IdTipoMensaje, hechos.Mensaje);

        return new(2, hechos.Mensaje, ReglasChecklistSalida.Evaluar(hechos.Datos));
    }
}

/// <summary>El técnico confirma o desmarca un ítem manual. Devuelve el checklist actualizado.</summary>
public class MarcarItemChecklistSalidaMovilCasoDeUso(IPresalidaMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<ChecklistSalidaMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, string? codigo, MarcarItemChecklistDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, "Servicio no encontrado o no asignado a tu usuario.");

        var codigoNormalizado = (codigo ?? string.Empty).Trim().ToLowerInvariant();
        if (!ReglasChecklistSalida.CodigosManuales.Contains(codigoNormalizado))
            return new(1, "Este ítem no lo confirma el técnico: se actualiza solo con los datos del servicio.");

        if (dto is null)
            return new(1, "Indica si el ítem queda confirmado.");

        var hechos = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        if (hechos.IdTipoMensaje != 2 || hechos.Datos is null)
            return new(hechos.IdTipoMensaje, hechos.Mensaje);

        if (codigoNormalizado == "pesas_patron" && !ReglasChecklistSalida.RequierePesasPatron(hechos.Datos.IdTipoServicio))
            return new(1, "Este tipo de servicio no usa pesas patrón.");

        var r = await repositorio.MarcarItemAsync(idUsuario, idOs, codigoNormalizado, dto.Confirmado, ct);
        if (r.IdTipoMensaje != 2)
            return new(r.IdTipoMensaje, r.Mensaje);

        var actualizados = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        return actualizados.IdTipoMensaje == 2 && actualizados.Datos is not null
            ? new(2, r.Mensaje, ReglasChecklistSalida.Evaluar(actualizados.Datos))
            : new(actualizados.IdTipoMensaje, actualizados.Mensaje);
    }
}

/// <summary>
/// El técnico pide el visto bueno al encargado del área del servicio (según la RQ). Los pendientes los calcula el back
/// (no se aceptan desde la app). El motivo es opcional y se limpia (máx. 300 caracteres, sin saltos de control).
/// </summary>
public class SolicitarAutorizacionSalidaMovilCasoDeUso(IPresalidaMovilRepositorio repositorio)
{
    public const int MaxMotivo = 300;

    public async Task<RespuestaDto<ChecklistSalidaMovilDto>> EjecutarAsync(
        long idUsuario, long idOs, SolicitarAutorizacionSalidaDto? dto, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, "Servicio no encontrado o no asignado a tu usuario.");

        var motivo = Limpiar(dto?.Motivo);
        if (motivo is { Length: > MaxMotivo })
            return new(1, $"El motivo puede tener hasta {MaxMotivo} caracteres.");

        var hechos = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        if (hechos.IdTipoMensaje != 2 || hechos.Datos is null)
            return new(hechos.IdTipoMensaje, hechos.Mensaje);

        var checklist = ReglasChecklistSalida.Evaluar(hechos.Datos);
        if (checklist.Faltantes.Count == 0)
            return new(1, "No tienes pendientes: puedes iniciar el traslado sin autorización.");
        if (!checklist.PuedeSolicitarAutorizacion)
            return new(1, checklist.Autorizacion?.Estado switch
            {
                "pendiente" => "Ya enviaste una solicitud: espera la respuesta del encargado del área.",
                "aprobada"  => "Ya tienes el visto bueno: puedes iniciar el traslado.",
                _           => "El servicio ya no está programado.",
            });

        var pendientes = string.Join(", ", checklist.Faltantes);
        if (pendientes.Length > 500) pendientes = pendientes[..500];

        var r = await repositorio.SolicitarAutorizacionAsync(idUsuario, idOs, motivo, pendientes, ct);
        if (r.IdTipoMensaje != 2)
            return new(r.IdTipoMensaje, r.Mensaje);

        var actualizados = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        return actualizados.IdTipoMensaje == 2 && actualizados.Datos is not null
            ? new(2, r.Mensaje, ReglasChecklistSalida.Evaluar(actualizados.Datos))
            : new(actualizados.IdTipoMensaje, actualizados.Mensaje);
    }

    internal static string? Limpiar(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        var limpio = new string(texto.Where(c => !char.IsControl(c) || c == '\n').ToArray()).Trim();
        return limpio.Length == 0 ? null : limpio;
    }
}

/// <summary>
/// Inicia el traslado. El back vuelve a evaluar el checklist (la app no decide): sin pendientes, o con
/// pendientes y visto bueno vigente del jefe. Si no se puede, responde qué falta.
/// </summary>
public class IniciarTrasladoMovilCasoDeUso(IPresalidaMovilRepositorio repositorio)
{
    public async Task<RespuestaDto<ChecklistSalidaMovilDto>> EjecutarAsync(long idUsuario, long idOs, CancellationToken ct = default)
    {
        if (idUsuario <= 0 || idOs <= 0)
            return new(1, "Servicio no encontrado o no asignado a tu usuario.");

        var hechos = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        if (hechos.IdTipoMensaje != 2 || hechos.Datos is null)
            return new(hechos.IdTipoMensaje, hechos.Mensaje);

        var checklist = ReglasChecklistSalida.Evaluar(hechos.Datos);
        if (!checklist.PuedeIniciar)
        {
            var mensaje = !ReglasChecklistSalida.EstaProgramada(checklist.EstadoOs)
                ? "El servicio ya no está programado."
                : $"No puedes iniciar el traslado. Faltan: {string.Join(", ", checklist.Faltantes)}.";
            return new(1, mensaje, checklist);
        }

        var r = await repositorio.IniciarTrasladoAsync(idUsuario, idOs, checklist.SaleConVistoBueno, ct);
        if (r.IdTipoMensaje != 2)
            return new(r.IdTipoMensaje, r.Mensaje);

        var actualizados = await repositorio.ObtenerHechosChecklistAsync(idUsuario, idOs, ct);
        return actualizados.IdTipoMensaje == 2 && actualizados.Datos is not null
            ? new(2, r.Mensaje, ReglasChecklistSalida.Evaluar(actualizados.Datos))
            : new(2, r.Mensaje);
    }
}

// ── Intranet: visto bueno del encargado del área ─────────────────────────────

/// <summary>Bandeja de autorizaciones de salida (el SP valida el cargo y filtra por el área del encargado).</summary>
public class ObtenerAutorizacionesSalidaCasoDeUso(IAutorizacionSalidaRepositorio repositorio)
{
    private static readonly HashSet<string> Estados = ["", "pendiente", "aprobada", "rechazada"];

    public Task<RespuestaDto<List<AutorizacionSalidaBandejaDto>>> EjecutarAsync(long idUsuario, string? estado, CancellationToken ct = default)
    {
        var e = (estado ?? string.Empty).Trim().ToLowerInvariant();
        if (!Estados.Contains(e))
            return Task.FromResult(new RespuestaDto<List<AutorizacionSalidaBandejaDto>>(1, "Estado no válido. Use pendiente, aprobada o rechazada."));

        return repositorio.ObtenerAsync(idUsuario, e, ct);
    }
}

/// <summary>El jefe aprueba o rechaza la salida. Al rechazar, el comentario es obligatorio.</summary>
public class ResolverAutorizacionSalidaCasoDeUso(IAutorizacionSalidaRepositorio repositorio)
{
    public const int MaxComentario = 500;

    public Task<RespuestaDto<bool>> EjecutarAsync(long idJefe, long idOs, ResolverAutorizacionSalidaDto? dto, CancellationToken ct = default)
    {
        if (idJefe <= 0 || idOs <= 0 || dto is null)
            return Task.FromResult(new RespuestaDto<bool>(1, "Datos incompletos."));

        var comentario = SolicitarAutorizacionSalidaMovilCasoDeUso.Limpiar(dto.Comentario);
        if (comentario is { Length: > MaxComentario })
            return Task.FromResult(new RespuestaDto<bool>(1, $"El comentario puede tener hasta {MaxComentario} caracteres."));
        if (!dto.Aprobar && comentario is null)
            return Task.FromResult(new RespuestaDto<bool>(1, "Indica el motivo por el que no autorizas la salida."));

        return repositorio.ResolverAsync(idJefe, idOs, dto.Aprobar, comentario, ct);
    }
}
