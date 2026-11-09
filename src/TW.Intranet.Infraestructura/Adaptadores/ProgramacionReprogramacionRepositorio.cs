using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-38 Reprogramación y Cancelación de la Programación (Sprint 5). Todo pasa por SPs parametrizados.</summary>
public class ProgramacionReprogramacionRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IProgramacionReprogramacionRepositorio
{
    private static bool Tiene(MySqlDataReader r, string col)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static string? TextoOpc(MySqlDataReader r, string col) => Tiene(r, col) ? Texto(r, col) : null;

    private static async Task<List<MotivoDto>> LeerMotivosAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<MotivoDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new MotivoDto(Entero(r, "id_motivo"), Texto(r, "nombre") ?? "", TextoOpc(r, "codigo")));
        return lista;
    }

    private static async Task<List<TecnicoReprogramacionDto>> LeerTecnicosAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<TecnicoReprogramacionDto>();
        while (await r.ReadAsync(ct))
            lista.Add(new TecnicoReprogramacionDto(EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? "", TextoOpc(r, "cargo"), Texto(r, "rol") ?? "apoyo"));
        return lista;
    }

    private static async Task<List<EquipoReprogramacionDto>> LeerEquiposAsync(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<EquipoReprogramacionDto>();
        var conReserva = r.FieldCount > 0 && Tiene(r, "reservado");
        while (await r.ReadAsync(ct))
            lista.Add(new EquipoReprogramacionDto(EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw"), Texto(r, "marca"), Texto(r, "modelo"),
                Texto(r, "num_serie"), conReserva && Booleano(r, "reservado")));
        return lista;
    }

    // ══════════════════════ Ficha "Reprogramar Servicio" ══════════════════════

    public Task<RespuestaDto<ProgramacionPreparadaDto>> PrepararReprogramacionAsync(long idProgramacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararReprogramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ProgramacionPreparadaDto>(1, "La programación no existe.");

                var idProg = EnteroLargo(r, "id_programacion");
                var codigo = Texto(r, "codigo") ?? "";
                var estado = Texto(r, "estado") ?? "";
                var label  = Texto(r, "estado_label") ?? "";
                var idOs   = EnteroLargo(r, "id_os");
                var numero = Texto(r, "numero_os") ?? "";
                var tipo   = Texto(r, "tipo") ?? "OS";
                var estOs  = Texto(r, "estado_os");
                var razon  = Texto(r, "razon_social");
                var sede   = Texto(r, "sede");
                var ubic   = Texto(r, "ubicacion");
                var tserv  = Texto(r, "tipo_servicio");
                var fecha  = Fecha(r, "fecha_ejecucion");
                var hIni   = Texto(r, "hora_inicio");
                var hFin   = Texto(r, "hora_fin");
                var durac  = DecimalNulo(r, "duracion_horas");
                var idTec  = EnteroLargoNulo(r, "id_tecnico_principal");
                var tec    = Texto(r, "tecnico_principal");
                var nEq    = Entero(r, "n_equipos_os");
                var viat   = DecimalNulo(r, "viaticos_depositados") ?? 0m;
                var modo   = Texto(r, "modo") ?? "solicitud";
                var idSol  = EnteroLargoNulo(r, "id_solicitud_pendiente");
                var puede  = Booleano(r, "puede_reprogramar");
                var motNo  = Texto(r, "motivo_no_reprogramable");
                var maxCom = Entero(r, "comentario_maximo");

                await r.NextResultAsync(ct);
                var tecnicos = await LeerTecnicosAsync(r, ct);
                await r.NextResultAsync(ct);
                var equipos = await LeerEquiposAsync(r, ct);
                await r.NextResultAsync(ct);
                var motivos = await LeerMotivosAsync(r, ct);

                return new RespuestaDto<ProgramacionPreparadaDto>(2, mensaje,
                    new ProgramacionPreparadaDto(idProg, codigo, estado, label, idOs, numero, tipo, estOs, razon, sede, ubic, tserv,
                        fecha, hIni, hFin, durac, idTec, tec, nEq, viat, modo, idSol, puede, motNo, maxCom, tecnicos, equipos, motivos));
            },
            ct);

    // ══════════════════════ Reprogramar (directa o solicitud) ══════════════════════

    public Task<RespuestaDto<ReprogramacionResultadoDto>> ReprogramarAsync(NuevaReprogramacion n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ReprogramarProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", n.IdProgramacion);
                p.AddWithValue("p_fecha",           n.Fecha is null ? DBNull.Value : n.Fecha.Value.Date);
                p.AddWithValue("p_hora_inicio",     Valor(n.HoraInicio));
                p.AddWithValue("p_hora_fin",        Valor(n.HoraFin));
                p.AddWithValue("p_id_tecnico",      Valor(n.IdTecnicoPrincipal));
                p.AddWithValue("p_ids_apoyo",       n.IdsApoyo   is null ? DBNull.Value : JsonSerializer.Serialize(n.IdsApoyo));
                p.AddWithValue("p_ids_equipos",     n.IdsEquipos is null ? DBNull.Value : JsonSerializer.Serialize(n.IdsEquipos));
                p.AddWithValue("p_id_motivo",       n.IdMotivo);
                p.AddWithValue("p_comentario",      Valor(n.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ReprogramacionResultadoDto>(3, "El cambio se guardó pero el procedimiento no devolvió su detalle.");

                return new RespuestaDto<ReprogramacionResultadoDto>(2, mensaje,
                    new ReprogramacionResultadoDto(
                        Texto(r, "modo") ?? "solicitud", EnteroLargoNulo(r, "id_solicitud"), EnteroLargo(r, "id_programacion"),
                        Texto(r, "codigo") ?? "", Texto(r, "estado") ?? "", Texto(r, "estado_label") ?? "",
                        Booleano(r, "requiere_reconfirmar_cliente"), Booleano(r, "cambia_fecha_hora"),
                        Booleano(r, "cambia_tecnicos"), Booleano(r, "cambia_equipos"),
                        Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), Texto(r, "hora_fin")));
            },
            ct);

    // ══════════════════════ Solicitud de reprogramación ══════════════════════

    public Task<RespuestaDto<SolicitudReprogramacionDto>> ObtenerSolicitudAsync(long idSolicitud, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSolicitudReprogramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_solicitud", idSolicitud);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<SolicitudReprogramacionDto>(1, "La solicitud no existe.");

                var s = new
                {
                    Id = EnteroLargo(r, "id_solicitud"), Estado = Texto(r, "estado") ?? "", Label = Texto(r, "estado_label") ?? "",
                    IdProg = EnteroLargo(r, "id_programacion"), Codigo = Texto(r, "codigo") ?? "",
                    IdOs = EnteroLargo(r, "id_os"), Numero = Texto(r, "numero_os") ?? "", Razon = Texto(r, "razon_social"),
                    Solicitante = Texto(r, "solicitante"), Cargo = Texto(r, "cargo_solicitante"), FechaSol = FechaHora(r, "fecha_solicitud"),
                    Motivo = Texto(r, "motivo"), Comentario = Texto(r, "comentario"),
                    FechaAct = Fecha(r, "fecha_actual"), HIniAct = Texto(r, "hora_inicio_actual"), HFinAct = Texto(r, "hora_fin_actual"),
                    DurAct = DecimalNulo(r, "duracion_actual_horas"), TecAct = Texto(r, "tecnico_actual"),
                    FechaProp = Fecha(r, "fecha_propuesta"), HIniProp = Texto(r, "hora_inicio_propuesta"), HFinProp = Texto(r, "hora_fin_propuesta"),
                    DurProp = DecimalNulo(r, "duracion_propuesta_horas"), Dias = EnteroNulo(r, "dias_diferencia"), TecProp = Texto(r, "tecnico_propuesto"),
                    CambiaTec = Booleano(r, "cambia_tecnico_principal"), Apoyo = Booleano(r, "propone_apoyo"), Equipos = Booleano(r, "propone_equipos"),
                    CambiaFh = Booleano(r, "cambia_fecha_hora"), NuevoLabel = Texto(r, "nuevo_estado_label"),
                    Viat = DecimalNulo(r, "viaticos_depositados") ?? 0m, ResPor = Texto(r, "resuelto_por_nombre"),
                    FechaRes = FechaHora(r, "fecha_resolucion"), ComRes = Texto(r, "comentario_resolucion"),
                    PuedeRes = Booleano(r, "puede_resolver"), PuedeRet = Booleano(r, "puede_retirar"),
                };

                await r.NextResultAsync(ct);
                var equipoTrabajo = await LeerTecnicosAsync(r, ct);
                await r.NextResultAsync(ct);
                var equipos = await LeerEquiposAsync(r, ct);

                return new RespuestaDto<SolicitudReprogramacionDto>(2, mensaje,
                    new SolicitudReprogramacionDto(s.Id, s.Estado, s.Label, s.IdProg, s.Codigo, s.IdOs, s.Numero, s.Razon, s.Solicitante, s.Cargo,
                        s.FechaSol, s.Motivo, s.Comentario, s.FechaAct, s.HIniAct, s.HFinAct, s.DurAct, s.TecAct, s.FechaProp, s.HIniProp, s.HFinProp,
                        s.DurProp, s.Dias, s.TecProp, s.CambiaTec, s.Apoyo, s.Equipos, s.CambiaFh, s.NuevoLabel, s.Viat, s.ResPor, s.FechaRes,
                        s.ComRes, s.PuedeRes, s.PuedeRet, equipoTrabajo, equipos));
            },
            ct);

    private static SolicitudResueltaDto LeerSolicitudResuelta(MySqlDataReader r)
        => new(EnteroLargo(r, "id_solicitud"), Texto(r, "estado_solicitud") ?? "", EnteroLargo(r, "id_programacion"),
            Texto(r, "codigo") ?? "", TextoOpc(r, "estado") ?? "", TextoOpc(r, "estado_label") ?? "",
            Tiene(r, "requiere_reconfirmar_cliente") && Booleano(r, "requiere_reconfirmar_cliente"));

    public Task<RespuestaDto<SolicitudResueltaDto>> ResolverSolicitudAsync(ResolucionSolicitudNormalizada n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverSolicitudReprogramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_solicitud", n.IdSolicitud);
                p.AddWithValue("p_decision",     n.Decision);
                p.AddWithValue("p_comentario",   Valor(n.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<SolicitudResueltaDto>(2, mensaje, LeerSolicitudResuelta(r))
                    : new RespuestaDto<SolicitudResueltaDto>(3, "La decisión se guardó pero el procedimiento no devolvió su detalle.");
            },
            ct);

    public Task<RespuestaDto<SolicitudResueltaDto>> RetirarSolicitudAsync(long idSolicitud, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RetirarSolicitudReprogramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_solicitud", idSolicitud);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<SolicitudResueltaDto>(2, mensaje, LeerSolicitudResuelta(r))
                    : new RespuestaDto<SolicitudResueltaDto>(3, "La solicitud se retiró pero el procedimiento no devolvió su detalle.");
            },
            ct);

    // ══════════════════════ Cancelación ══════════════════════

    public Task<RespuestaDto<CancelacionPreparadaDto>> PrepararCancelacionAsync(long idProgramacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararCancelacionProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CancelacionPreparadaDto>(1, "La programación no existe.");

                var idProg = EnteroLargo(r, "id_programacion");
                var codigo = Texto(r, "codigo") ?? "";
                var estado = Texto(r, "estado") ?? "";
                var label  = Texto(r, "estado_label") ?? "";
                var idOs   = EnteroLargo(r, "id_os");
                var numero = Texto(r, "numero_os") ?? "";
                var tipo   = Texto(r, "tipo") ?? "OS";
                var estOs  = Texto(r, "estado_os");
                var razon  = Texto(r, "razon_social");
                var puede  = Booleano(r, "puede_cancelar");
                var motNo  = Texto(r, "motivo_no_cancelable");
                var viat   = DecimalNulo(r, "viaticos_depositados") ?? 0m;
                var idSol  = EnteroLargoNulo(r, "id_solicitud_pendiente");
                var min    = Entero(r, "comentario_minimo");
                var max    = Entero(r, "comentario_maximo");

                await r.NextResultAsync(ct);
                var motivos = await LeerMotivosAsync(r, ct);

                return new RespuestaDto<CancelacionPreparadaDto>(2, mensaje,
                    new CancelacionPreparadaDto(idProg, codigo, estado, label, idOs, numero, tipo, estOs, razon, puede, motNo, viat, idSol, min, max, motivos));
            },
            ct);

    public Task<RespuestaDto<CancelacionResultadoDto>> CancelarAsync(NuevaCancelacion n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CancelarProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", n.IdProgramacion);
                p.AddWithValue("p_id_motivo",       n.IdMotivo);
                p.AddWithValue("p_comentario",      Valor(n.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CancelacionResultadoDto>(3, "La programación se canceló pero el procedimiento no devolvió su detalle.");

                return new RespuestaDto<CancelacionResultadoDto>(2, mensaje,
                    new CancelacionResultadoDto(
                        EnteroLargo(r, "id_programacion"), Texto(r, "codigo") ?? "", Texto(r, "estado") ?? "", Texto(r, "estado_label") ?? "",
                        EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? "", Texto(r, "estado_os"), Texto(r, "motivo"),
                        DecimalNulo(r, "viaticos_depositados") ?? 0m, Entero(r, "solicitudes_canceladas"), Texto(r, "siguiente_accion")));
            },
            ct);

    // ══════════════════════ Historial de programaciones de una OS ══════════════════════

    public Task<RespuestaDto<HistorialProgramacionesOsDto>> ObtenerHistorialOsAsync(long idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerHistorialProgramacionesOs",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabeceras = new List<(ProgramacionHistorialDto Dto, long Id)>();
                while (await r.ReadAsync(ct))
                {
                    var dto = new ProgramacionHistorialDto(
                        EnteroLargo(r, "id_programacion"), Texto(r, "codigo") ?? "", Texto(r, "estado") ?? "", Texto(r, "estado_label") ?? "",
                        Booleano(r, "es_activa"), Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"),
                        Texto(r, "tecnico_principal"), FechaHora(r, "creado_en"), Texto(r, "creado_por_nombre"),
                        FechaHora(r, "cancelada_en"), Texto(r, "cancelada_por_nombre"), Texto(r, "motivo_cancelacion"),
                        Texto(r, "comentario_cancelacion"), Entero(r, "n_solicitudes"), Entero(r, "n_reprogramaciones"), []);
                    cabeceras.Add((dto, dto.IdProgramacion));
                }

                await r.NextResultAsync(ct);
                var eventos = new Dictionary<long, List<EventoHistorialProgramacionDto>>();
                while (await r.ReadAsync(ct))
                {
                    var id = EnteroLargo(r, "id_programacion");
                    if (!eventos.TryGetValue(id, out var lista)) eventos[id] = lista = [];
                    lista.Add(new EventoHistorialProgramacionDto(FechaHora(r, "fecha"), Texto(r, "tipo"), Texto(r, "titulo"),
                        Texto(r, "descripcion"), Texto(r, "usuario"), Texto(r, "estado_anterior"), Texto(r, "estado_nuevo"), Texto(r, "motivo")));
                }

                var programaciones = cabeceras
                    .Select(c => c.Dto with { Timeline = eventos.TryGetValue(c.Id, out var t) ? t : [] })
                    .ToList();
                return new RespuestaDto<HistorialProgramacionesOsDto>(2, mensaje, new HistorialProgramacionesOsDto(idOs, programaciones));
            },
            ct);
}
