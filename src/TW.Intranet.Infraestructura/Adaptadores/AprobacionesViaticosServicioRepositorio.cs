using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-52 / HU-57 (Sprint 5) Aprobaciones y viáticos de una OS. Todo pasa por SPs parametrizados.</summary>
public class AprobacionesViaticosServicioRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IAprobacionesViaticosServicioRepositorio
{
    public Task<RespuestaDto<AprobacionesServicioDto>> ObtenerAprobacionesAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAprobacionesServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<AprobacionServicioDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new AprobacionServicioDto(Texto(r, "tipo") ?? "", EnteroLargo(r, "id"), Texto(r, "titulo"), Texto(r, "solicitante"),
                        FechaHora(r, "solicitado_en"), Texto(r, "motivo"), Texto(r, "detalle"), Texto(r, "estado") ?? "pendiente",
                        Texto(r, "resuelto_por"), Texto(r, "cargo"), FechaHora(r, "resuelto_en"), Texto(r, "comentario"),
                        Booleano(r, "urgente"), Booleano(r, "puede_resolver")));

                await r.NextResultAsync(ct);
                var totales = new TotalesAprobacionesDto(0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    totales = new TotalesAprobacionesDto(Entero(r, "total"), Entero(r, "pendientes"), Entero(r, "aprobadas"), Entero(r, "rechazadas"));

                return new RespuestaDto<AprobacionesServicioDto>(2, mensaje, new AprobacionesServicioDto(lista, totales));
            },
            ct);

    public Task<RespuestaDto<bool>> ResolverAprobacionAsync(long idUsuario, long idOs, string tipo, long id, bool aprobar, string comentario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverAprobacionServicioRuta",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_tipo",       tipo);
                p.AddWithValue("p_id",         id);
                p.AddWithValue("p_aprobar",    Bit(aprobar));
                p.AddWithValue("p_comentario", comentario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)),
            ct);

    public Task<RespuestaDto<ViaticosOsDto>> ObtenerViaticosServicioAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerViaticosServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            (r, mensaje) => LeerViaticosAsync(r, mensaje, conCierre: false, ct),
            ct);

    public Task<RespuestaDto<ViaticosOsDto>> ObtenerViaticosInformeAsync(long idUsuario, long idInforme, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerViaticosInforme",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_informe", idInforme); },
            (r, mensaje) => LeerViaticosAsync(r, mensaje, conCierre: true, ct),
            ct);

    public Task<RespuestaDto<RevisarGastoResultadoDto>> RevisarGastoServicioAsync(
        long idUsuario, long idOs, long idGasto, string accion, string? comentario, CancellationToken ct)
        => EjecutarAsync("SP_RevisarGastoServicioRuta",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_id_gasto",   idGasto);
                p.AddWithValue("p_accion",     accion);
                p.AddWithValue("p_comentario", Valor(comentario));
            },
            async (r, mensaje) =>
            {
                // Mismos resultados que SP_RevisarGastoProgramacion: 2 gasto resultante, 3 tarjetas de la rendición
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RevisarGastoResultadoDto>(3, "El cambio se guardó pero el procedimiento no devolvió su detalle.");
                var id = EnteroLargo(r, "id_programacion"); var g = EnteroLargo(r, "id_gasto");
                var estado = Texto(r, "estado") ?? ""; var tec = EnteroLargo(r, "id_tecnico");
                await r.NextResultAsync(ct);
                var resumen = await r.ReadAsync(ct) ? ProgramacionViaticosRepositorio.LeerResumen(r) : ProgramacionViaticosRepositorio.ResumenVacio;
                return new RespuestaDto<RevisarGastoResultadoDto>(2, mensaje, new RevisarGastoResultadoDto(id, g, estado, tec, resumen));
            },
            ct);

    public Task<RespuestaDto<string>> ObtenerRutaComprobanteAsync(long idUsuario, long idOs, long idGasto, int n, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerComprobanteGastoServicioRuta",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
                p.AddWithValue("p_id_gasto",   idGasto);
                p.AddWithValue("p_n",          n);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct) && Texto(r, "ruta") is { } ruta
                    ? new RespuestaDto<string>(2, mensaje, ruta)
                    : new RespuestaDto<string>(1, "El gasto no tiene ese comprobante.");
            },
            ct);

    /// <summary>Lee 2 cabecera, 3 resumen, 4 líneas, 5 gastos y (Revisión de Informes) 6 cierre de la rendición.</summary>
    private static async Task<RespuestaDto<ViaticosOsDto>> LeerViaticosAsync(MySqlDataReader r, string mensaje, bool conCierre, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        if (!await r.ReadAsync(ct))
            return new RespuestaDto<ViaticosOsDto>(3, "El procedimiento no devolvió la cabecera de los viáticos.");
        var cab = new ViaticosOsCabeceraDto(EnteroLargoNulo(r, "id_programacion"), Texto(r, "codigo"), Texto(r, "estado"),
            Booleano(r, "puede_revisar"), Booleano(r, "puede_gestionar"), Booleano(r, "rendicion_cerrada"), Texto(r, "moneda") ?? "S/");

        await r.NextResultAsync(ct);
        var resumen = new ViaticosOsResumenDto(0m, 0m, 0m, 0m, 0m, 0m, 0m, 0, 0m, 0m, "cuadrado");
        if (await r.ReadAsync(ct))
            resumen = new ViaticosOsResumenDto(DecimalNulo(r, "asignado") ?? 0m, DecimalNulo(r, "depositado") ?? 0m,
                DecimalNulo(r, "pendiente_deposito") ?? 0m, DecimalNulo(r, "rendido") ?? 0m, DecimalNulo(r, "aprobado") ?? 0m,
                DecimalNulo(r, "rechazado") ?? 0m, DecimalNulo(r, "por_revisar") ?? 0m, Entero(r, "n_por_revisar"),
                DecimalNulo(r, "por_rendir") ?? 0m, DecimalNulo(r, "saldo") ?? 0m, Texto(r, "tipo_saldo") ?? "cuadrado");

        await r.NextResultAsync(ct);
        var lineas = new List<ViaticoLineaOsDto>();
        while (await r.ReadAsync(ct))
            lineas.Add(new ViaticoLineaOsDto(EnteroLargo(r, "id_gasto"), EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? "",
                Texto(r, "rol") ?? "apoyo", Entero(r, "id_concepto"), Texto(r, "concepto") ?? "", DecimalNulo(r, "asignado") ?? 0m,
                DecimalNulo(r, "rendido") ?? 0m, DecimalNulo(r, "por_rendir") ?? 0m, Texto(r, "estado_deposito") ?? "pendiente",
                Fecha(r, "fecha_deposito")));

        await r.NextResultAsync(ct);
        var gastos = new List<GastoRendidoOsDto>();
        while (await r.ReadAsync(ct))
            gastos.Add(new GastoRendidoOsDto(EnteroLargo(r, "id_gasto"), Fecha(r, "fecha"), EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? "",
                Entero(r, "id_concepto"), Texto(r, "concepto") ?? "", Texto(r, "descripcion"), DecimalNulo(r, "monto") ?? 0m,
                Texto(r, "estado") ?? "pendiente", Texto(r, "comentario_revision"), Texto(r, "revisado_por"), FechaHora(r, "revisado_en"),
                Entero(r, "n_fotos"), Texto(r, "motivo_sin_foto"), DecimalNulo(r, "monto_ia"),
                DecimalNulo(r, "coincide_ia") is { } c ? c != 0 : null, Booleano(r, "puede_revisar"), Texto(r, "origen")));

        // D. Reparto de los gastos entre las líneas del adelanto
        await r.NextResultAsync(ct);
        var repartos = new List<RepartoGastoOsDto>();
        while (await r.ReadAsync(ct))
            repartos.Add(new RepartoGastoOsDto(EnteroLargo(r, "id_gasto"), EnteroLargo(r, "id_viatico_linea"), Texto(r, "concepto") ?? "",
                DecimalNulo(r, "monto") ?? 0m));

        CierreRendicionOsDto? cierre = null;
        if (conCierre)
        {
            await r.NextResultAsync(ct);
            if (await r.ReadAsync(ct))
                cierre = new CierreRendicionOsDto(Texto(r, "estado") ?? "abierta", DecimalNulo(r, "asignado") ?? 0m, DecimalNulo(r, "aprobado") ?? 0m,
                    DecimalNulo(r, "rechazado") ?? 0m, DecimalNulo(r, "saldo") ?? 0m, Texto(r, "tipo") ?? "cuadrado",
                    Texto(r, "cerrado_por"), FechaHora(r, "cerrado_en"));
        }

        return new RespuestaDto<ViaticosOsDto>(2, mensaje, new ViaticosOsDto(cab, resumen, lineas, gastos, cierre, repartos));
    }
}
