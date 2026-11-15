using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-45 Asignación de Viáticos y Rendición de Gastos Operativos (Sprint 5). Todo pasa por SPs parametrizados.</summary>
public class ProgramacionViaticosRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IProgramacionViaticosRepositorio
{
    internal static ResumenRendicionDto LeerResumen(MySqlDataReader r) => new(
        EnteroLargo(r, "id_programacion"), DecimalNulo(r, "total_asignado") ?? 0m, DecimalNulo(r, "total_depositado") ?? 0m,
        DecimalNulo(r, "total_pendiente_deposito") ?? 0m, DecimalNulo(r, "total_solicitado") ?? 0m, Entero(r, "n_gastos"),
        Entero(r, "n_comprobantes"), DecimalNulo(r, "total_aprobado") ?? 0m, Entero(r, "n_aprobados"), DecimalNulo(r, "total_observado") ?? 0m,
        DecimalNulo(r, "total_pendiente") ?? 0m, DecimalNulo(r, "total_rechazado") ?? 0m, DecimalNulo(r, "saldo_vs_asignado") ?? 0m,
        Texto(r, "tipo_saldo") ?? "cuadrado", Entero(r, "pendientes_revision"), Booleano(r, "cerrada"), Booleano(r, "puede_cerrar"),
        Texto(r, "motivo_no_cerrar"), Texto(r, "advertencia_cierre"));

    internal static readonly ResumenRendicionDto ResumenVacio =
        new(0, 0m, 0m, 0m, 0m, 0, 0, 0m, 0, 0m, 0m, 0m, 0m, "cuadrado", 0, false, false, null, null);

    public Task<RespuestaDto<ViaticosProgramacionDto>> ObtenerAsync(long idProgramacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerViaticosProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ViaticosProgramacionDto>(1, "La programación no existe.");
                var cab = new ViaticosCabeceraDto(EnteroLargo(r, "id_programacion"), Texto(r, "codigo") ?? "", Texto(r, "estado") ?? "",
                    Texto(r, "estado_label") ?? "", EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? "", Texto(r, "tipo") ?? "OS",
                    Texto(r, "razon_social"), Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"),
                    EnteroLargoNulo(r, "id_tecnico_principal"), Texto(r, "tecnico_principal"), Texto(r, "cargo_principal"),
                    Booleano(r, "puede_gestionar"), Texto(r, "motivo_no_gestionar"), Booleano(r, "rendicion_cerrada"),
                    Texto(r, "version") ?? "", Texto(r, "moneda") ?? "S/",
                    Booleano(r, "puede_editar_asignacion"), Texto(r, "motivo_no_editar_asignacion"));

                await r.NextResultAsync(ct);
                var tecnicos = new List<ViaticosTecnicoDto>();
                while (await r.ReadAsync(ct))
                    tecnicos.Add(new ViaticosTecnicoDto(EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? "", Texto(r, "cargo"),
                        Texto(r, "rol") ?? "apoyo", Booleano(r, "vigente"), DecimalNulo(r, "subtotal_asignado") ?? 0m, DecimalNulo(r, "rendido_aprobado") ?? 0m));

                await r.NextResultAsync(ct);
                var conceptos = new List<ConceptoGastoDto>();
                while (await r.ReadAsync(ct))
                    conceptos.Add(new ConceptoGastoDto(Entero(r, "id_concepto"), Texto(r, "nombre") ?? "", Texto(r, "categoria") ?? "", Booleano(r, "personalizado")));

                await r.NextResultAsync(ct);
                var lineas = new List<LineaAsignacionDto>();
                while (await r.ReadAsync(ct))
                    lineas.Add(new LineaAsignacionDto(EnteroLargo(r, "id_gasto"), EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? "",
                        Texto(r, "rol") ?? "apoyo", Entero(r, "id_concepto"), Texto(r, "concepto") ?? "", DecimalNulo(r, "monto") ?? 0m,
                        Texto(r, "estado_deposito") ?? "pendiente", Fecha(r, "fecha_deposito"), Booleano(r, "notificado"), Booleano(r, "editable")));

                await r.NextResultAsync(ct);
                var totales = new TotalesAsignacionDto(0m, 0m, 0m, 0m, 0);
                if (await r.ReadAsync(ct))
                    totales = new TotalesAsignacionDto(DecimalNulo(r, "total_asignado") ?? 0m, DecimalNulo(r, "total_depositado") ?? 0m,
                        DecimalNulo(r, "total_pendiente") ?? 0m, DecimalNulo(r, "pendiente_por_notificar") ?? 0m, Entero(r, "lineas_por_notificar"));

                await r.NextResultAsync(ct);
                var gastos = new List<GastoRendidoDto>();
                while (await r.ReadAsync(ct))
                    gastos.Add(new GastoRendidoDto(EnteroLargo(r, "id_gasto"), Fecha(r, "fecha"), EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? "",
                        Entero(r, "id_concepto"), Texto(r, "concepto") ?? "", Texto(r, "descripcion"), DecimalNulo(r, "monto") ?? 0m,
                        Booleano(r, "tiene_comprobante"), Texto(r, "estado") ?? "pendiente", Texto(r, "comentario_revision"),
                        Booleano(r, "puede_aprobar"), Booleano(r, "puede_observar"), Booleano(r, "puede_rechazar")));

                await r.NextResultAsync(ct);
                var resumen = await r.ReadAsync(ct) ? LeerResumen(r) : ResumenVacio;

                await r.NextResultAsync(ct);
                CierreRendicionDto? cierre = null;
                if (await r.ReadAsync(ct))
                    cierre = new CierreRendicionDto(Texto(r, "cerrado_en"), Texto(r, "cerrado_por"), DecimalNulo(r, "total_asignado") ?? 0m,
                        DecimalNulo(r, "total_aprobado") ?? 0m, DecimalNulo(r, "saldo") ?? 0m, Texto(r, "tipo_saldo") ?? "cuadrado");

                return new RespuestaDto<ViaticosProgramacionDto>(2, mensaje,
                    new ViaticosProgramacionDto(cab, tecnicos, conceptos, lineas, totales, gastos, resumen, cierre));
            },
            ct);

    public Task<RespuestaDto<GuardarViaticosResultadoDto>> GuardarAsync(long idProgramacion, GuardarViaticosNormalizado n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarViaticosProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
                p.AddWithValue("p_version",         n.Version);
                p.AddWithValue("p_lineas",          n.LineasJson);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<GuardarViaticosResultadoDto>(3, "El cambio se guardó pero el procedimiento no devolvió su detalle.");
                return new RespuestaDto<GuardarViaticosResultadoDto>(2, mensaje,
                    new GuardarViaticosResultadoDto(EnteroLargo(r, "id_programacion"), Entero(r, "creadas"), Entero(r, "modificadas"), Entero(r, "retiradas"),
                        DecimalNulo(r, "total_asignado") ?? 0m, DecimalNulo(r, "total_depositado") ?? 0m, DecimalNulo(r, "total_pendiente") ?? 0m,
                        Entero(r, "notificados_contabilidad"), Booleano(r, "sin_cambios"), Entero(r, "conceptos_nuevos"), Texto(r, "version") ?? ""));
            },
            ct);

    public Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoAsync(
        long idProgramacion, long idGasto, string accion, string? comentario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RevisarGastoProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
                p.AddWithValue("p_id_gasto",        idGasto);
                p.AddWithValue("p_accion",          accion);
                p.AddWithValue("p_comentario",      Valor(comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RevisarGastoResultadoDto>(3, "El cambio se guardó pero el procedimiento no devolvió su detalle.");
                var id = EnteroLargo(r, "id_programacion"); var g = EnteroLargo(r, "id_gasto");
                var estado = Texto(r, "estado") ?? ""; var tec = EnteroLargo(r, "id_tecnico");
                await r.NextResultAsync(ct);
                var resumen = await r.ReadAsync(ct) ? LeerResumen(r) : ResumenVacio;
                return new RespuestaDto<RevisarGastoResultadoDto>(2, mensaje, new RevisarGastoResultadoDto(id, g, estado, tec, resumen));
            },
            ct);

    public Task<RespuestaDto<CerrarRendicionResultadoDto>> CerrarRendicionAsync(long idProgramacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CerrarRendicionProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CerrarRendicionResultadoDto>(3, "El cierre se guardó pero el procedimiento no devolvió su detalle.");
                return new RespuestaDto<CerrarRendicionResultadoDto>(2, mensaje,
                    new CerrarRendicionResultadoDto(EnteroLargo(r, "id_programacion"), DecimalNulo(r, "total_asignado") ?? 0m,
                        DecimalNulo(r, "total_depositado") ?? 0m, DecimalNulo(r, "total_solicitado") ?? 0m, DecimalNulo(r, "total_aprobado") ?? 0m,
                        DecimalNulo(r, "total_rechazado") ?? 0m, DecimalNulo(r, "saldo") ?? 0m, Texto(r, "tipo_saldo") ?? "cuadrado",
                        Entero(r, "notificados_contabilidad")));
            },
            ct);

    public Task<RespuestaDto<ComprobanteGastoDto>> ObtenerComprobanteAsync(long idProgramacion, long idGasto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerComprobanteGasto",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
                p.AddWithValue("p_id_gasto",        idGasto);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ComprobanteGastoDto>(1, "El comprobante no existe.");
                return new RespuestaDto<ComprobanteGastoDto>(2, mensaje,
                    new ComprobanteGastoDto(EnteroLargo(r, "id_gasto"), Texto(r, "url") ?? "", DecimalNulo(r, "monto") ?? 0m,
                        Texto(r, "estado") ?? "", Fecha(r, "fecha"), Texto(r, "concepto") ?? "", Texto(r, "tecnico") ?? ""));
            },
            ct);
}
